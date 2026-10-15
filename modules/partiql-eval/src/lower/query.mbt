///|
/// The variables that FROM and LET declare, in the order they are declared,
/// with the scope of the enclosing query (spec M4b1 §4).
priv struct Scope {
  names : Array[String]
  outer : Scope?
  /// Inside a FROM source, a plain name finds a global before a variable.
  globals_first : Bool
  /// The names are the output names of a SELECT list (for ORDER BY): a name
  /// finds them first, but they are not candidates for an implicit
  /// attribute.
  outputs : Bool
  /// The names are WITH bindings: a name finds them as a `Local` also in a
  /// FROM source, and they are not candidates for an implicit attribute
  /// (plan ruling 10).
  with_ : Bool
  /// The names are output names that a variable hides: a name finds a
  /// variable first and an output name only when no variable has that name
  /// (a sort key that is not a bare name).
  variables_first : Bool
  /// The names are grouping variables (keys and GROUP AS): they are not
  /// candidates for an implicit attribute.
  grouped : Bool
  /// Whether a SQL aggregate may stand here.
  aggregates : Aggregates
  /// A scope out from this one is grouped (a subquery of a grouped query).
  under_group : Bool
}

///|
/// Whether a SQL aggregate may stand where a scope is (spec M4c §7).
priv enum Aggregates {
  /// Not here: FROM, LET, WHERE, GROUP BY, outside a query.
  Forbidden
  /// SELECT, HAVING and ORDER BY of a grouped query.
  Allowed(Grouped)
  /// The argument of an aggregate: a nested aggregate is an error.
  Inside
}

///|
/// The grouped context of a query.
priv struct Grouped {
  /// The forms of the keys that a repeated expression matches.
  keys : Array[KeyForm]
  /// The FROM and LET variables that are not keys: an aggregate argument
  /// binds them per member (the `p.` of spec section 11.2.2).
  members : Array[String]
  /// The group variable: GROUP AS, else `@plan.group_variable`.
  group : String
  /// The grouped scope (keys and GROUP AS) without the grouped context.
  base : Scope
  /// The only FROM or LET variable of the query, if there is one: then a
  /// name `a` that no variable declares is the attribute `v.a`.
  single : String?
  /// The FROM and LET variables that grouping hides: outside an aggregate,
  /// naming one is a static error.
  hidden : Array[String]
}

///|
/// The scope outside every query: no variables.
fn Scope::top() -> Scope {
  {
    names: [],
    outer: None,
    globals_first: false,
    outputs: false,
    with_: false,
    variables_first: false,
    grouped: false,
    aggregates: Forbidden,
    under_group: false,
  }
}

///|
/// A scope inside `self` that declares `names`.
fn Scope::inner(self : Scope, names : Array[String]) -> Scope {
  {
    names,
    outer: Some(self),
    globals_first: false,
    outputs: false,
    with_: false,
    variables_first: false,
    grouped: false,
    aggregates: Forbidden,
    under_group: self.grouped || self.under_group,
  }
}

///|
/// A scope inside `self` with the output names of a SELECT list.
fn Scope::with_outputs(self : Scope, names : Array[String]) -> Scope {
  { ..self.inner(names), outputs: true, aggregates: self.aggregates, }
}

///|
/// A scope inside `self` with the WITH names `names`.
fn Scope::with_scope(self : Scope, names : Array[String]) -> Scope {
  { ..self.inner(names), with_: true, }
}

///|
/// The same scope, for the expression of a FROM source.
fn Scope::for_source(self : Scope) -> Scope {
  { ..self, globals_first: true, }
}

///|
/// The declared name of the innermost variable that `id` names: a regular
/// identifier ignores case, a delimited one does not. Also whether that
/// variable is a WITH binding.
fn Scope::resolve(self : Scope, id : @ast.Identifier) -> (String, Bool)? {
  let wanted = if id.delimited { id.text } else { id.text.to_lower() }
  let mut scope = Some(self)
  let mut hidden = None
  while scope is Some(s) {
    for name in s.names.rev_iter() {
      let key = if id.delimited { name } else { name.to_lower() }
      if key == wanted {
        // An output name is a frame of its own, so it never hides a
        // variable of the same name at run time.
        let shown = if s.outputs { @plan.output_variable(name) } else { name }
        if s.outputs && s.variables_first {
          if hidden is None {
            hidden = Some((shown, s.with_))
          }
          break
        }
        return Some((shown, s.with_))
      }
    }
    scope = s.outer
  }
  hidden
}

///|
/// The names of every variable in scope, the innermost query first and each
/// query in FROM order. Output names are left out.
fn Scope::locals(self : Scope) -> Array[String] {
  let all = []
  let mut scope = Some(self)
  while scope is Some(s) {
    if !s.outputs && !s.with_ && !s.grouped {
      all.append(s.names)
    }
    scope = s.outer
  }
  all
}

///|
/// Lowers a query statement.
pub fn lower_query(q : @ast.Query) -> @plan.Expr raise @plan.EvalError {
  within_depth(query_at(q, Scope::top(), 0))
}

///|
/// Lowers a query `depth` levels down. A form that a later part of M4 adds
/// is `Unsupported`, named with that part.
fn query_at(
  q : @ast.Query,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  if !q.with_.is_empty() {
    return with_at(q, scope, depth)
  }
  // LIMIT and OFFSET see the outer scope, not the variables of this query.
  let limit = clause_at(q.limit, "LIMIT", scope, depth)
  let offset = clause_at(q.offset, "OFFSET", scope, depth)
  // The body, the output names a sort key may use, and the scope of the
  // sort keys.
  let (body, aliases, keys_scope) = match q.body {
    Select(s) => {
      let (body, aliases, inner) = select_parts(s, q.order_by, scope, depth)
      (body, aliases, inner.with_outputs(aliases))
    }
    Expr(e) =>
      (lower_at(e, scope, depth), [], scope.inner([@plan.row_variable]))
    SetOp(op) =>
      (set_op_at(op, scope, depth), [], scope.inner([@plan.row_variable]))
    Table(parts) => {
      let (body, inner) = table_at(parts, scope, depth, q.span)
      (body, [], inner.with_outputs([]))
    }
  }
  // A key that is exactly a name finds an output name first; any other key
  // finds a variable first and an output name only when no variable has it.
  let expr_scope = { ..keys_scope, variables_first: true, }
  if q.order_by.is_empty() && limit is None && offset is None {
    return body
  }
  let order = q.order_by.map(spec => {
    let desc = spec.order is Some(Desc)
    let nulls_first = match spec.nulls {
      Some(First) => true
      Some(Last) => false
      None => desc
    }
    @plan.SortKey::{
      expr: lower_at(
        spec.expr,
        if spec.expr.kind is VarRef(_, ..) {
          keys_scope
        } else {
          expr_scope
        },
        depth,
      ),
      desc,
      nulls_first,
    }
  })
  Query(body, order~, limit~, offset~, aliases~, q.span)
}

///|
/// Lowers a query with WITH: each binding is a query that sees the earlier
/// names, the outer scope and not the later names; the rest of the query
/// (body, ORDER BY, LIMIT, OFFSET) sees all of them. A repeated name is a
/// `DataError`.
fn with_at(
  q : @ast.Query,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  if depth >= max_depth {
    raise DataError(message="query is too deeply nested", span=q.span)
  }
  let names = []
  let bindings = []
  for b in q.with_ {
    let expr = query_at(b.query, scope.with_scope(names.copy()), depth + 1)
    if names.contains(b.name.text) {
      raise DataError(
        message="WITH name \{b.name.text} is declared twice",
        span=b.name.span,
      )
    }
    names.push(b.name.text)
    bindings.push((b.name.text, expr))
  }
  let rest = query_at({ ..q, with_: [], }, scope.with_scope(names), depth + 1)
  With(bindings, rest, q.span)
}

///|
/// Lowers `TABLE a.b` as `SELECT * FROM a.b` (plan ruling 12): the plan and
/// the scope inside it.
fn table_at(
  parts : Array[@ast.Identifier],
  scope : Scope,
  depth : Int32,
  span : @ast.Span,
) -> (@plan.Expr, Scope) raise @plan.EvalError {
  guard parts is [first, .. rest] else {
    raise DataError(message="TABLE needs a name", span~)
  }
  let base : @ast.Expr = {
    kind: VarRef(first, qualified=false),
    span: first.span,
  }
  let expr : @ast.Expr = if rest.is_empty() {
    base
  } else {
    { kind: Path(base, rest.map(id => Field(id))), span, }
  }
  let source : @ast.FromSource = {
    lateral: false,
    expr,
    as_: None,
    at: None,
    by: None,
    span,
  }
  let names = []
  let rel = from_leaf(Scan(source), scope, names, Ref(0), depth)
  (
    Select(rel, Star(from_variables(rel)), distinct=false, span),
    scope.inner(names),
  )
}

///|
/// Lowers a chain of set operations. The chain is walked down its left
/// spine in a loop, through every left operand that is a set operation
/// without clauses of its own (`A UNION B UNION C` is `(A UNION B) UNION
/// C`), so a long chain takes no recursion per link. The operands see the
/// scope of the query.
fn set_op_at(
  op : @ast.SetOp,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  if depth >= max_depth {
    raise DataError(message="query is too deeply nested", span=op.span)
  }
  let steps = [op]
  let mut leaf = op.left
  while leaf is { body: SetOp(inner), .. } && !has_clauses(leaf) {
    steps.push(inner)
    leaf = inner.left
  }
  let mut acc = query_at(leaf, scope, depth + 1)
  for step in steps.rev_iter() {
    let right = query_at(step.right, scope, depth + 1)
    acc = SetOp(
      step.op,
      all=step.quantifier is Some(All),
      outer=step.outer,
      corresponding=step.corresponding,
      acc,
      right,
      step.span,
    )
  }
  acc
}

///|
/// Whether a query has a clause of its own: WITH, ORDER BY, LIMIT or
/// OFFSET.
fn has_clauses(q : @ast.Query) -> Bool {
  !q.with_.is_empty() ||
  !q.order_by.is_empty() ||
  q.limit is Some(_) ||
  q.offset is Some(_)
}

///|
/// Whether `e` is an integer literal below 0: a minus sign on a literal.
fn negative_literal(e : @ast.Expr) -> Bool {
  match e.kind {
    Unary(Neg, { kind: Lit(Int(text)), .. }) =>
      text.iter().any(c => c >= '1' && c <= '9')
    _ => false
  }
}

///|
/// Lowers a LIMIT or OFFSET expression in `scope`. A negative literal is a
/// `DataError` in both modes (plan ruling 3).
fn clause_at(
  clause : @ast.Expr?,
  name : String,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr? raise @plan.EvalError {
  guard clause is Some(e) else { return None }
  if negative_literal(e) {
    raise DataError(message="\{name} must not be negative", span=e.span)
  }
  match e.kind {
    // A count beyond Int64 is valid (OFFSET skips all rows, LIMIT keeps
    // them all), so this literal is not range-checked.
    Lit(Int(text)) =>
      Some(
        Const(@value.Value::integer(@bigint.BigInt::from_string(text)), e.span),
      )
    _ => Some(lower_at(e, scope, depth))
  }
}

///|
/// Lowers a query block: the plan, the output names of its SELECT list (in
/// order, none for `SELECT VALUE` and `*`), and the scope inside it (its FROM
/// and LET variables).
fn select_parts(
  s : @ast.Select,
  order_by : Array[@ast.SortSpec],
  scope : Scope,
  depth : Int32,
) -> (@plan.Expr, Array[String], Scope) raise @plan.EvalError {
  let names = []
  let sources = Ref(0)
  let from = match s.from {
    Some(item) => from_item(item, scope, names, sources, depth)
    None => return unsupported("SELECT without FROM (M4b1)", s.span)
  }
  let variables = from_variables(from)
  // A LET expression sees the variables before it, so `names` grows as the
  // bindings are lowered.
  let bindings = []
  for l in s.let_ {
    bindings.push((l.name.text, lower_at(l.expr, scope.inner(names), depth)))
    names.push(l.name.text)
  }
  let inner = scope.inner(names)
  let let_rel : @plan.Rel = if bindings.is_empty() {
    from
  } else {
    Let(from, bindings, s.let_[0].span)
  }
  let rel : @plan.Rel = match s.where_ {
    Some(w) => Filter(let_rel, lower_at(w, inner, depth), w.span)
    None => let_rel
  }
  let roots = projection_exprs(s.projection)
  if s.having is Some(h) {
    roots.push(h)
  }
  order_by.each(spec => roots.push(spec.expr))
  let is_grouped = s.group_by is Some(_) ||
    s.having is Some(_) ||
    contains_aggregate(roots)
  if !is_grouped {
    let (projection, aliases) = projection_at(
      s.projection,
      Star(variables),
      inner,
      depth,
    )
    return (
      Select(rel, projection, distinct=s.quantifier is Some(Distinct), s.span),
      aliases,
      inner,
    )
  }
  let (grouped_rel, gscope, visible) = group_at(
    s, rel, names, scope, inner, depth,
  )
  let star : @plan.Projection = Items(
    visible.map(name => @plan.Item::Named(name, Local(name, s.span))),
  )
  let (projection, aliases) = projection_at(s.projection, star, gscope, depth)
  (
    Select(
      grouped_rel,
      projection,
      distinct=s.quantifier is Some(Distinct),
      s.span,
    ),
    aliases,
    gscope,
  )
}

///|
/// Lowers a SELECT clause in `scope`: the projection and its output names.
/// `star` is what `SELECT *` means here.
fn projection_at(
  p : @ast.Projection,
  star : @plan.Projection,
  scope : Scope,
  depth : Int32,
) -> (@plan.Projection, Array[String]) raise @plan.EvalError {
  let aliases = []
  let projection : @plan.Projection = match p {
    Value(e) => Value(lower_at(e, scope, depth))
    Star(_) => star
    Items(items) => {
      let unnamed = Ref(0)
      let out : Array[@plan.Item] = []
      for item in items {
        out.push(
          match item {
            Expr(e, as_~, ..) => {
              let name = match as_ {
                Some(id) => id.text
                None => item_name(e, unnamed)
              }
              aliases.push(name)
              @plan.Item::Named(name, lower_at(e, scope, depth))
            }
            AllFields(e, ..) => @plan.Item::AllFields(lower_at(e, scope, depth))
          },
        )
      }
      Items(out)
    }
    Pivot(value~, key~) =>
      Pivot(
        value=lower_at(value, scope, depth),
        key=lower_at(key, scope, depth),
      )
  }
  (projection, aliases)
}

///|
/// The expressions of a SELECT clause.
fn projection_exprs(p : @ast.Projection) -> Array[@ast.Expr] {
  match p {
    Value(e) => [e]
    Star(_) => []
    Items(items) =>
      items.map(item => {
        match item {
          Expr(e, ..) | AllFields(e, ..) => e
        }
      })
    Pivot(value~, key~) => [value, key]
  }
}

///|
/// The expression of the SELECT item called `id`, when `id` names no FROM or
/// LET variable of the query (spec section 11.2.4: GROUP BY may name a
/// SELECT alias; a variable comes first).
fn select_alias(
  id : @ast.Identifier,
  projection : @ast.Projection,
  names : Array[String],
) -> @ast.Expr? {
  let same = (name : String) => {
    if id.delimited {
      name == id.text
    } else {
      name.to_lower() == id.text.to_lower()
    }
  }
  if names.iter().any(same) {
    return None
  }
  guard projection is Items(items) else { return None }
  for item in items {
    if item is Expr(e, as_=Some(item_as), ..) && same(item_as.text) {
      return Some(e)
    }
  }
  None
}

///|
/// The GROUP BY and HAVING of a grouped query over `rel`: the relation, the
/// grouped scope (keys and GROUP AS over the outer `scope`, spec section
/// 11.2), and the names `SELECT *` outputs. `names` are the FROM and LET
/// variables; `inner` is their scope, where the keys are lowered.
fn group_at(
  s : @ast.Select,
  rel : @plan.Rel,
  names : Array[String],
  scope : Scope,
  inner : Scope,
  depth : Int32,
) -> (@plan.Rel, Scope, Array[String]) raise @plan.EvalError {
  let key_items = match s.group_by {
    Some({ keys: By(keys, ..), .. }) => keys
    _ => []
  }
  let keys : Array[(String, @plan.Expr)] = []
  let visible = []
  let forms : Array[KeyForm] = []
  let group_as : @ast.Identifier? = match s.group_by {
    Some(g) => g.group_as
    None => None
  }
  // The names that the query gives: an implied key name gives way to them.
  let given = key_items.filter_map(k => k.as_.map(id => id.text))
  if group_as is Some(id) {
    if given.contains(id.text) {
      raise DataError(
        message="GROUP AS name \{id.text} is also a GROUP BY name",
        span=id.span,
      )
    }
    given.push(id.text)
  }
  for i, k in key_items {
    let (expr, select_name) = match k.expr.kind {
      VarRef(id, qualified=false) =>
        match select_alias(id, s.projection, names) {
          Some(e) => (e, Some(id.text))
          None => (k.expr, None)
        }
      _ => (k.expr, None)
    }
    let name = match k.as_ {
      Some(id) => {
        if visible.contains(id.text) {
          raise DataError(
            message="GROUP BY name \{id.text} is declared twice",
            span=id.span,
          )
        }
        id.text
      }
      // Spec section 11.2.1 gives a key without AS a fresh name. The name
      // it implies is used when it is free, else its position.
      None => {
        let implied = select_name.unwrap_or(implicit_name(k.expr, i))
        let positional = "_\{i + 1}"
        if !visible.contains(implied) && !given.contains(implied) {
          implied
        } else if !visible.contains(positional) && !given.contains(positional) {
          positional
        } else {
          hidden_key(i)
        }
      }
    }
    visible.push(name)
    keys.push((name, lower_at(expr, inner, depth)))
    forms.push(key_form(expr, name, own_only=false))
    if expr.kind is VarRef(id, qualified=false) &&
      inner.resolve(id) is None &&
      names is [variable] {
      for form in attribute_forms(id, variable) {
        forms.push(key_form(form, name, own_only=true))
      }
    }
  }
  if group_as is Some(id) {
    visible.push(id.text)
  }
  let grouping : @plan.Grouping = match s.group_by {
    Some({ keys: By(_, ..), .. }) => By(keys)
    _ => All
  }
  let group = match group_as {
    Some(id) => id.text
    None => @plan.group_variable
  }
  let free = names.filter(name => {
    !visible.contains(name) || (group_as is Some(id) && id.text == name)
  })
  let base = { ..scope.inner(visible), grouped: true, }
  let gscope = {
    ..base,
    aggregates: Allowed({
      keys: forms,
      members: free,
      group,
      base,
      single: if names is [variable] {
        Some(variable)
      } else {
        None
      },
      hidden: names.filter(name => !visible.contains(name)),
    }),
  }
  let span = match s.group_by {
    Some(g) => g.span
    None => s.span
  }
  let grouped : @plan.Rel = Group(
    rel,
    grouping,
    group_as=group,
    members=names.copy(),
    span,
  )
  let filtered : @plan.Rel = match s.having {
    Some(h) => Filter(grouped, lower_at(h, gscope, depth), h.span)
    None => grouped
  }
  (filtered, gscope, visible.filter(name => !name.has_prefix("\u{0}")))
}

///|
/// The name of the key at `position` when its implied name and its position
/// are both taken: no identifier can name it, and `SELECT *` leaves it out.
fn hidden_key(position : Int32) -> String {
  "\u{0}key\{position + 1}"
}

///|
/// The variable of a FROM source: its `AS` name, else the name of the
/// variable or of the last field of the path it scans, else `_` and its
/// position among the sources of the query block, from 1 (partiql-lang-kotlin's
/// rule; `SELECT * FROM <<{'a': 1}>>, <<{'b': 2}>>` needs two names).
fn from_name(source : @ast.FromSource, position : Int32) -> String {
  match source.as_ {
    Some(id) => id.text
    None => implicit_name(source.expr, position)
  }
}

///|
/// The name an expression implies: the name of the variable or of the last
/// field of the path.
fn implied_name(e : @ast.Expr) -> String? {
  match e.kind {
    VarRef(id, ..) => Some(id.text)
    Path(_, [.., Field(id)]) => Some(id.text)
    Path(_, [.., FieldString(name, ..)]) => Some(name)
    _ => None
  }
}

///|
/// The name of an expression without `AS` in a list where position counts
/// (FROM sources, GROUP BY keys): the implied name, else `_` and the
/// position `index` (from 0) plus 1.
fn implicit_name(e : @ast.Expr, index : Int32) -> String {
  implied_name(e).unwrap_or("_\{index + 1}")
}

///|
/// The name of a SELECT item without `AS`: the implied name, else `_` and the
/// count of unnamed items so far (partiql-lang-kotlin and partiql-tests;
/// the specification leaves it open, partiql-lang #85).
fn item_name(e : @ast.Expr, unnamed : Ref[Int32]) -> String {
  match implied_name(e) {
    Some(name) => name
    None => {
      unnamed.val += 1
      "_\{unnamed.val}"
    }
  }
}

///|
/// The variables that a FROM binds, without the `AT` ones, in FROM order. A
/// loop with a stack of pending relations, so a long chain of joins takes no
/// recursion.
fn from_variables(rel : @plan.Rel) -> Array[String] {
  let names = []
  let pending = [rel]
  while pending.pop() is Some(r) {
    match r {
      Scan(_, as_~, at=_, _) | Unpivot(_, as_~, at=_, _) => names.push(as_)
      Filter(input, _, _) | Let(input, _, _) => pending.push(input)
      Join(_, l, r, on=_, _) => {
        pending.push(r)
        pending.push(l)
      }
      // A FROM never holds a group.
      Group(_, _, group_as=_, members=_, _) => ()
    }
  }
  names
}

///|
/// Lowers a FROM item and appends the variables it declares to `names`, in
/// order. A source sees the variables that come before it (lateral). A list
/// of sources is a chain of joins on the left: the loop walks that chain, so
/// a long list takes no recursion per item.
fn from_item(
  item : @ast.FromItem,
  scope : Scope,
  names : Array[String],
  sources : Ref[Int32],
  depth : Int32,
) -> @plan.Rel raise @plan.EvalError {
  if depth >= max_depth {
    raise DataError(
      message="FROM list is too deeply nested",
      span=from_span(item),
    )
  }
  let joins = []
  let mut leaf = item
  while leaf is Join(j) {
    joins.push(j)
    leaf = j.left
  }
  let mut rel = from_leaf(leaf, scope, names, sources, depth)
  for j in joins.rev_iter() {
    let kind : @plan.JoinKind = match (j.kind, j.form) {
      (Full, _) => return unsupported("FULL JOIN (later)", j.span)
      (Inner, Comma | Cross) => Cross
      (Inner, On(_)) => Inner
      (Left, _) => Left
      (Right, _) => Right
    }
    // The right side of a RIGHT JOIN is read once, outside the left rows.
    let right = if kind is Right {
      let own = []
      let right = from_item(j.right, scope, own, sources, depth + 1)
      for name in own {
        declare_variable(names, name, j.span)
      }
      right
    } else {
      from_item(j.right, scope, names, sources, depth + 1)
    }
    let on = match j.form {
      On(e) => Some(lower_at(e, scope.inner(names), depth))
      Comma | Cross => None
    }
    rel = Join(kind, rel, right, on~, j.span)
  }
  rel
}

///|
/// Declares the FROM variable `name` in `names`. A repeat of a name in one
/// FROM clause is an error, as in SQL. Declared names compare exactly: the
/// conformance suite keeps `an_alias` and `AN_ALIAS` apart as two variables
/// (a lookup by regular identifier finds both and is ambiguous).
fn declare_variable(
  names : Array[String],
  name : String,
  span : @ast.Span,
) -> Unit raise @plan.EvalError {
  if names.contains(name) {
    raise DataError(
      message="FROM variable \{name} is declared twice; name one of them with AS",
      span~,
    )
  }
  names.push(name)
}

///|
fn from_leaf(
  item : @ast.FromItem,
  scope : Scope,
  names : Array[String],
  sources : Ref[Int32],
  depth : Int32,
) -> @plan.Rel raise @plan.EvalError {
  let (source, unpivot) = match item {
    Scan(source) => (source, false)
    Unpivot(source) => (source, true)
    // `from_item` walks every join down to a source.
    Join(j) => return unsupported("a join in a source position", j.span)
  }
  if source.by is Some(id) {
    return unsupported("FROM ... BY (later)", id.span)
  }
  let as_ = from_name(source, sources.val)
  sources.val += 1
  let at = source.at.map(id => id.text)
  let expr = lower_plain(source.expr, scope.inner(names).for_source(), depth)
  if source.at is Some(id) {
    declare_variable(names, id.text, id.span)
  }
  declare_variable(names, as_, source.span)
  if unpivot {
    Unpivot(expr, as_~, at~, source.span)
  } else {
    Scan(expr, as_~, at~, source.span)
  }
}

///|
fn from_span(item : @ast.FromItem) -> @ast.Span {
  match item {
    Scan(s) | Unpivot(s) => s.span
    Join(j) => j.span
  }
}

///|
/// Whether `e` is a subquery `(SELECT item FROM ...)` with exactly one
/// projection item that is not `SELECT VALUE`, `*` or `x.*`.
fn is_single_column(e : @ast.Expr) -> Bool {
  match e.kind {
    Query({ body: Select({ projection: Items([Expr(_, ..)]), .. }), .. }) =>
      true
    _ => false
  }
}

///|
/// Lowers an expression where a FROM source, the collection of an `IN` or a
/// statement stands: a subquery there is not coerced.
fn lower_plain(
  e : @ast.Expr,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  match e.kind {
    Query(q) => {
      if depth >= max_depth {
        raise DataError(message="expression is too deep", span=e.span)
      }
      query_at(q, scope, depth + 1)
    }
    _ => lower_at(e, scope, depth)
  }
}

///|
/// Lowers the collection of an `IN`: a single-column `SELECT` there is the
/// bag of the value of each row.
fn column_at(
  e : @ast.Expr,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  let inner = lower_plain(e, scope, depth)
  if is_single_column(e) {
    Subquery(inner, Column, e.span)
  } else {
    inner
  }
}

///|
/// Whether `e` is a subquery whose body is a `SELECT` with a list of
/// expression items (any number, not `SELECT VALUE`, `*` or `x.*`).
fn is_select_items(e : @ast.Expr) -> Bool {
  match e.kind {
    Query({ body: Select({ projection: Items(items), .. }), .. }) =>
      items.iter().all(item => item is Expr(_, ..))
    _ => false
  }
}

///|
/// Lowers a subquery that is compared with an array literal: its row is
/// coerced to a list (plan ruling 9).
fn row_at(
  e : @ast.Expr,
  scope : Scope,
  depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  Subquery(lower_plain(e, scope, depth), Row, e.span)
}
