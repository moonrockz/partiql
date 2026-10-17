// Aggregate functions in lowering (spec M4c §7).

///|
/// The aggregate function that `id` names, and whether it is a COLL_ form.
/// Names compare without case; a delimited name is never an aggregate.
fn aggregate_function(id : @ast.Identifier) -> (@plan.AggregateKind, Bool)? {
  if id.delimited {
    return None
  }
  match id.text.to_upper() {
    "COUNT" => Some((Count, false))
    "SUM" => Some((Sum, false))
    "AVG" => Some((Avg, false))
    "MIN" => Some((Min, false))
    "MAX" => Some((Max, false))
    "ANY" | "SOME" => Some((Any, false))
    "EVERY" => Some((Every, false))
    "COLL_COUNT" => Some((Count, true))
    "COLL_SUM" => Some((Sum, true))
    "COLL_AVG" => Some((Avg, true))
    "COLL_MIN" => Some((Min, true))
    "COLL_MAX" => Some((Max, true))
    "COLL_ANY" | "COLL_SOME" => Some((Any, true))
    "COLL_EVERY" => Some((Every, true))
    _ => None
  }
}

///|
/// `COLL_f([DISTINCT | ALL] e)`. The argument is a collection, so a subquery
/// there is not coerced to a scalar.
fn coll_call(
  kind : @plan.AggregateKind,
  id : @ast.Identifier,
  args : Array[@ast.Expr],
  quantifier : @ast.SetQuantifier?,
  scope : Scope,
  depth : Int32,
  span : @ast.Span,
) -> @plan.Expr raise @plan.EvalError {
  guard args is [arg] else {
    raise DataError(message="\{id.text} takes one argument", span~)
  }
  CollAggregate(
    kind,
    distinct=quantifier is Some(Distinct),
    lower_plain(arg, scope, depth),
    span,
  )
}

///|
/// A SQL aggregate call `f([DISTINCT | ALL] e)` or `COUNT(*)` in its scope.
fn sql_aggregate_call(
  e : @ast.Expr,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  let span = e.span
  let (id, args, quantifier, star) = match e.kind {
    Call(id, args, quantifier~) => (id, args, quantifier, false)
    CallStar(id) => (id, [], None, true)
    _ => raise DataError(message="not an aggregate call", span~)
  }
  guard aggregate_function(id) is Some((kind, false)) else {
    raise DataError(message="\{id.text} is not an aggregate function", span~)
  }
  let g = match scope.aggregates {
    Allowed(g) => g
    Inside =>
      raise DataError(
        message="an aggregate function cannot be inside the argument of another",
        span~,
      )
    Forbidden =>
      raise DataError(
        message="\{id.text} is an aggregate function: it can be only in SELECT, HAVING and ORDER BY",
        span~,
      )
  }
  if star {
    if kind != Count {
      raise DataError(message="only COUNT takes *", span~)
    }
    // COUNT(*) is COLL_COUNT of the group (spec section 11.2.2).
    return CollAggregate(Count, distinct=false, Local(g.group, span), span)
  }
  guard args is [arg] else {
    raise DataError(message="\{id.text} takes one argument", span~)
  }
  let inner = { ..g.base.inner(g.members), aggregates: Inside, }
  Aggregate(
    kind,
    distinct=quantifier is Some(Distinct),
    lower_at(arg, inner, depth),
    members=g.members,
    group=g.group,
    span,
  )
}

///|
/// The expression of an optional operand, if there is one.
fn optional(e : @ast.Expr?) -> Array[@ast.Expr] {
  match e {
    Some(x) => [x]
    None => []
  }
}

///|
/// The direct subexpressions of `e` in its own query: a subquery and a graph
/// match are scopes of their own, so they have none here.
fn ast_operands(e : @ast.Expr) -> Array[@ast.Expr] {
  match e.kind {
    Lit(_)
    | VarRef(_, ..)
    | Parameter
    | CurrentDatetime(_, ..)
    | Error
    | Query(_)
    | GraphMatch(_)
    | CallStar(_) => []
    Path(base, steps) => {
      let out = [base]
      for step in steps {
        if step is Index(x) {
          out.push(x)
        }
      }
      out
    }
    Unary(_, x)
    | Not(x)
    | BoolTest(x, _, ..)
    | IsNull(x, ..)
    | IsMissing(x, ..)
    | IsType(x, _, ..)
    | Cast(x, _)
    | Extract(_, x) => [x]
    Binary(_, a, b)
    | And(a, b)
    | Or(a, b)
    | In(a, b, ..)
    | Overlaps(a, b)
    | Position(a, b)
    | NullIf(a, b)
    | DateAdd(_, a, b)
    | DateDiff(_, a, b) => [a, b]
    Like(x, pattern~, escape~, ..) => [x, pattern, ..optional(escape)]
    Between(x, low~, high~, ..) => [x, low, high]
    Case(operand~, branches~, default~) => {
      let out = optional(operand)
      for b in branches {
        out.push(b.0)
        out.push(b.1)
      }
      out.append(optional(default))
      out
    }
    Trim(chars~, x, ..) => [..optional(chars), x]
    Substring(x, start~, length~) => [x, start, ..optional(length)]
    Overlay(x, placing~, from~, for_~) => [x, placing, from, ..optional(for_)]
    Coalesce(xs)
    | Call(_, xs, ..)
    | List(xs)
    | Bag(xs)
    | Sexp(xs)
    | Row(xs)
    | Values(xs) => xs
    Struct(pairs) | Map(pairs) => {
      let out = []
      for p in pairs {
        out.push(p.0)
        out.push(p.1)
      }
      out
    }
  }
}

///|
/// Whether a SQL aggregate call is among `roots` in their own query.
fn contains_aggregate(roots : Array[@ast.Expr]) -> Bool {
  let pending = roots.copy()
  while pending.pop() is Some(e) {
    match e.kind {
      Call(id, _, ..) | CallStar(id) if aggregate_function(id)
        is Some((_, false)) => return true
      _ => pending.append(ast_operands(e))
    }
  }
  false
}

///|
/// A form of a GROUP BY key that lowering matches (spec section 11.2.1): an
/// expression and the key variable it stands for.
priv struct KeyForm {
  /// The key expression (a SELECT alias is replaced by its item).
  expr : @ast.Expr
  /// The key variable.
  name : String
  /// The number of links on the left spine of `expr` (see `spine_links`):
  /// a chain is compared only with a key of the same length.
  links : Int32
  /// The form `v.a` of a bare key `a`, where `v` is the only variable of the
  /// query: it holds in the query itself, not in its subqueries.
  own_only : Bool
}

///|
/// The number of binary operator, AND and OR links on the left spine of
/// `e`, as `lower_chain` walks it. A loop, so a long chain takes no
/// recursion.
fn spine_links(e : @ast.Expr) -> Int32 {
  let mut n = 0
  let mut x = e
  while true {
    match x.kind {
      Binary(_, l, _) | And(l, _) | Or(l, _) => {
        n += 1
        x = l
      }
      _ => break
    }
  }
  n
}

///|
/// The key forms of the key expression `expr` called `name`.
fn key_form(expr : @ast.Expr, name : String, own_only~ : Bool) -> KeyForm {
  { expr, name, links: spine_links(expr), own_only, }
}

///|
/// A placeholder for an operand in `shell`.
let hole : @ast.Expr = { kind: Error, span: { start: 0, end: 0, }, }

///|
/// `e` with each direct operand (`ast_operands`) replaced by a hole, in
/// canonical form. Two expressions are the same when their shells are equal
/// and their operands, in order, are the same. A subquery or a graph match is
/// returned whole; `same_expr` compares those apart.
fn shell(e : @ast.Expr) -> @ast.Expr {
  let h = hole
  let kind : @ast.ExprKind = match e.kind {
    Lit(_)
    | VarRef(_, ..)
    | Parameter
    | CurrentDatetime(_, ..)
    | Error
    | Query(_)
    | GraphMatch(_)
    | CallStar(_) => e.kind
    Path(_, steps) =>
      Path(h, steps.map(step => if step is Index(_) { Index(h) } else { step }))
    Unary(op, _) => Unary(op, h)
    Not(_) => Not(h)
    BoolTest(_, truth, negated~) => BoolTest(h, truth, negated~)
    IsNull(_, negated~) => IsNull(h, negated~)
    IsMissing(_, negated~) => IsMissing(h, negated~)
    IsType(_, t, negated~) => IsType(h, t, negated~)
    Cast(_, t) => Cast(h, t)
    Extract(f, _) => Extract(f, h)
    Binary(op, _, _) => Binary(op, h, h)
    And(_, _) => And(h, h)
    Or(_, _) => Or(h, h)
    In(_, _, negated~) => In(h, h, negated~)
    Overlaps(_, _) => Overlaps(h, h)
    Position(_, _) => Position(h, h)
    NullIf(_, _) => NullIf(h, h)
    DateAdd(f, _, _) => DateAdd(f, h, h)
    DateDiff(f, _, _) => DateDiff(f, h, h)
    Like(_, pattern=_, escape~, negated~) =>
      Like(h, pattern=h, escape=escape.map(_ => h), negated~)
    Between(_, low=_, high=_, negated~) => Between(h, low=h, high=h, negated~)
    Case(operand~, branches~, default~) =>
      Case(
        operand=operand.map(_ => h),
        branches=branches.map(_ => (h, h)),
        default=default.map(_ => h),
      )
    Trim(spec~, chars~, _) => Trim(spec~, chars=chars.map(_ => h), h)
    Substring(_, start=_, length~) =>
      Substring(h, start=h, length=length.map(_ => h))
    Overlay(_, placing=_, from=_, for_~) =>
      Overlay(h, placing=h, from=h, for_=for_.map(_ => h))
    Coalesce(xs) => Coalesce(xs.map(_ => h))
    Call(id, xs, quantifier~) => Call(id, xs.map(_ => h), quantifier~)
    List(xs) => List(xs.map(_ => h))
    Bag(xs) => Bag(xs.map(_ => h))
    Sexp(xs) => Sexp(xs.map(_ => h))
    Row(xs) => Row(xs.map(_ => h))
    Values(xs) => Values(xs.map(_ => h))
    Struct(pairs) => Struct(pairs.map(_ => (h, h)))
    Map(pairs) => Map(pairs.map(_ => (h, h)))
  }
  @ast.Expr::{ kind, span: e.span, }.canonical()
}

///|
/// Whether `a` and `b` are the same expression: equal up to spans and the
/// case of regular identifiers (spec M4c §3.5.2). A loop with a stack of
/// pending pairs, so a long chain takes no recursion. The work stops at the
/// first difference, so it is bounded by the size of the smaller one.
fn same_expr(a : @ast.Expr, b : @ast.Expr) -> Bool {
  let pending = [(a, b)]
  while pending.pop() is Some((x, y)) {
    match (x.kind, y.kind) {
      (Query(_), Query(_)) | (GraphMatch(_), GraphMatch(_)) =>
        // A scope of its own: compared whole.
        if x.canonical() != y.canonical() {
          return false
        }
      (Query(_) | GraphMatch(_), _) | (_, Query(_) | GraphMatch(_)) =>
        return false
      _ => {
        if shell(x) != shell(y) {
          return false
        }
        let ys = ast_operands(y)
        for i, operand in ast_operands(x) {
          pending.push((operand, ys[i]))
        }
      }
    }
  }
  true
}

///|
/// Whether `id` names the declared variable `name`: a regular identifier
/// ignores case, a delimited one does not.
fn names_variable(id : @ast.Identifier, name : String) -> Bool {
  if id.delimited {
    name == id.text
  } else {
    name.to_lower() == id.text.to_lower()
  }
}

///|
/// Whether `scope` declares a variable that `id` names.
fn Scope::declares(self : Scope, id : @ast.Identifier) -> Bool {
  self.names.iter().any(name => names_variable(id, name))
}

///|
/// The grouped query whose keys an expression in `scope` can repeat
/// (spec section 11.2.1: in the whole SELECT, HAVING or ORDER BY clause,
/// subqueries included), with the scopes from `scope` out to the grouped
/// scope, and whether `scope` is in the grouped query itself. In the
/// argument of an aggregate there is none: the FROM variables are bound
/// there.
priv struct KeyContext {
  grouped : Grouped
  walk : Array[Scope]
  own : Bool
}

///|
fn key_context(scope : Scope) -> KeyContext? {
  if !scope.grouped && !scope.under_group {
    return None
  }
  let walk = []
  let mut found = None
  let mut own = true
  let mut current = Some(scope)
  while current is Some(s) {
    walk.push(s)
    match s.aggregates {
      Inside => return None
      Allowed(g) => if found is None { found = Some(g) }
      Forbidden => if found is None && !s.outputs && !s.with_ { own = false }
    }
    if s.grouped {
      break
    }
    current = s.outer
  }
  match found {
    Some(g) if !g.keys.is_empty() => Some({ grouped: g, walk, own, })
    _ => None
  }
}

///|
/// Whether `e` means here what it means in the grouped query: no scope on
/// the way declares a variable that `e` names (an output name only counts
/// for a bare sort key), and none hides the key variable `name`.
fn KeyContext::sees(self : KeyContext, e : @ast.Expr, name : String) -> Bool {
  let pending = [e]
  while pending.pop() is Some(x) {
    if x.kind is VarRef(id, ..) &&
      self.walk
      .iter()
      .any(s => !(s.outputs && s.variables_first) && s.declares(id)) {
      return false
    }
    pending.append(ast_operands(x))
  }
  self.walk.iter().all(s => s.grouped || s.outputs || !s.names.contains(name))
}

///|
/// The key variable that `e` repeats, `links` being the number of links on
/// its left spine.
fn KeyContext::find(self : KeyContext, e : @ast.Expr, links : Int32) -> String? {
  for key in self.grouped.keys {
    if key.links == links &&
      (self.own || !key.own_only) &&
      same_expr(e, key.expr) &&
      self.sees(e, key.name) {
      return Some(key.name)
    }
  }
  // In the query itself, a name that no variable declares is an attribute
  // of its only variable `v`: `a` is the key `v.a`.
  if self.own &&
    e.kind is VarRef(id, qualified=false) &&
    self.grouped.single is Some(variable) &&
    self.sees(e, "") {
    for form in attribute_forms(id, variable) {
      for key in self.grouped.keys {
        if key.links == 0 && same_expr(form, key.expr) {
          return Some(key.name)
        }
      }
    }
  }
  None
}

///|
/// The key variable that `e` repeats, in the SELECT, HAVING or ORDER BY of a
/// grouped query or of a subquery inside them (spec section 11.2.1). A chain
/// (`lower_chain`) is matched there, with the length of its spine.
fn key_variable(e : @ast.Expr, scope : Scope) -> String? {
  guard key_context(scope) is Some(context) else { return None }
  context.find(e, 0)
}

///|
/// The longest prefix of the path `base` `steps` that is a key, as the key
/// variable and the number of steps it covers: `t.a.x` with the key `t.a`
/// is the attribute `x` of the key value. The whole path is matched by
/// `key_variable`.
fn key_prefix(
  base : @ast.Expr,
  steps : Array[@ast.PathStep],
  span : @ast.Span,
  scope : Scope,
) -> (String, Int32)? {
  guard key_context(scope) is Some(context) else { return None }
  let mut best : (String, Int32)? = None
  for key in context.grouped.keys {
    guard key.expr.kind is Path(_, key_steps) else { continue }
    let n = key_steps.length()
    if n >= steps.length() ||
      (best is Some((_, longest)) && longest >= n) ||
      !(context.own || !key.own_only) {
      continue
    }
    let prefix : @ast.Expr = {
      kind: Path(base, Array::from_iter(steps[0:n].iter())),
      span,
    }
    if same_expr(prefix, key.expr) && context.sees(prefix, key.name) {
      best = Some((key.name, n))
    }
  }
  best
}

///|
/// The forms of the path `variable.id`: a name that no variable declares is
/// an attribute of the only variable of the query, so `a` and `t.a` are the
/// same key (partiql-tests group-by.ion "qualified SELECT and ORDER BY"). The
/// declared name may have been regular or delimited, so both spellings are
/// given.
fn attribute_forms(id : @ast.Identifier, variable : String) -> Array[@ast.Expr] {
  [false, true].map(delimited => {
    let base : @ast.Expr = {
      kind: VarRef(
        { text: variable, delimited, span: id.span, },
        qualified=false,
      ),
      span: id.span,
    }
    @ast.Expr::{ kind: Path(base, [Field(id)]), span: id.span, }
  })
}

///|
/// The plan for `e` when it repeats a key: `key`. In a FROM source a name
/// finds a global before a variable (`GlobalOrLocal`), so there it is `e`
/// without key variables when one of its names is a global.
fn keyed(
  e : @ast.Expr,
  key : @plan.Expr,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  if !scope.globals_first {
    return key
  }
  let globals = []
  let pending = [e]
  while pending.pop() is Some(x) {
    if x.kind is VarRef(id, qualified=false) {
      globals.push((id.text, id.delimited, id.span))
    }
    pending.append(ast_operands(x))
  }
  let plain = { ..scope, grouped: false, under_group: false, }
  GlobalsFirst(globals, key~, otherwise=lower_at(e, plain, depth), e.span)
}
