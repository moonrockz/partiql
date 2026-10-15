// Grouping and aggregates (spec M4c §5).

///|
/// The fold of an aggregate function over values.
fn fold(
  kind : @plan.AggregateKind,
  values : Iter[@value.Value],
  distinct : Bool,
) -> @value.Value raise @ops.OpFailure {
  match kind {
    Count => @ops.count_values(values, distinct~)
    Sum => @ops.sum_values(values, distinct~)
    Avg => @ops.avg_values(values, distinct~)
    Min => @ops.min_values(values, distinct~)
    Max => @ops.max_values(values, distinct~)
    Any => @ops.any_values(values, distinct~)
    Every => @ops.every_values(values, distinct~)
  }
}

///|
/// `COLL_f(v)`: NULL for NULL, MISSING for MISSING, the fold of the elements
/// of a list or bag, and a type failure for any other value (the committee
/// rules of partiql-tests PR #80).
fn coll_aggregate(
  kind : @plan.AggregateKind,
  distinct : Bool,
  v : @value.Value,
  ctx : Ctx,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  match unboxed(v) {
    Null => Null
    Missing => Missing
    List(items) =>
      typed(ctx.mode, span, () => fold(kind, items.iter(), distinct))
    Bag(b) =>
      typed(ctx.mode, span, () => fold(kind, b.items().iter(), distinct))
    _ =>
      typed(ctx.mode, span, () => {
        raise TypeFailure("an aggregate function needs a collection")
      })
  }
}
