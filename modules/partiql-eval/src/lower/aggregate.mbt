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
/// A SQL aggregate call (Task 5 gives it the grouped context).
fn sql_aggregate_call(
  e : @ast.Expr,
  _scope : Scope,
  _depth : Int32,
) -> @plan.Expr raise @plan.EvalError {
  unsupported("GROUP BY (M4c)", e.span)
}
