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
/// The key variable that `e` repeats, in the SELECT, HAVING or ORDER BY of a
/// grouped query (spec section 11.2.1). A name that already resolves (a key,
/// GROUP AS, an output name, an outer variable) keeps its meaning.
fn key_variable(e : @ast.Expr, scope : Scope) -> String? {
  guard scope.aggregates is Allowed(g) && !g.keys.is_empty() else {
    return None
  }
  if e.kind is VarRef(id, ..) && scope.resolve(id) is Some(_) {
    return None
  }
  let form = e.canonical()
  for key in g.keys {
    if key.0 == form {
      return Some(key.1)
    }
  }
  None
}
