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

///|
/// A key value: MISSING (and an Ion-boxed null) is NULL (spec section
/// 11.1.1).
fn key_value(v : @value.Value) -> @value.Value {
  match unboxed(v) {
    Missing | Null => Null
    _ => v
  }
}

///|
/// The attribute `name` of a member tuple, else MISSING.
fn member_value(t : @value.Value, name : String) -> @value.Value {
  match t {
    Tuple(tuple) =>
      for field in tuple.fields() {
        if field.0 == name {
          break field.1
        }
      } nobreak {
        Missing
      }
    _ => Missing
  }
}

///|
/// The groups of the binding tuples of `input`, in order of first
/// appearance, each as a binding tuple inside `env`: the key variables over
/// `group_as` (the bag of the member tuples). `All` makes one group, also
/// for no input. Groups are found by bucket (`group_key` of the list of key
/// values) and compared with `eqg`.
fn group(
  input : @plan.Rel,
  grouping : @plan.Grouping,
  group_as : String,
  members : Array[String],
  env : Env,
  ctx : Ctx,
) -> Iter[Env] raise @plan.EvalError {
  let keys = match grouping {
    All => []
    By(keys) => keys
  }
  let groups : Array[(Array[@value.Value], Array[@value.Value])] = []
  let index : Map[String, Array[(@value.Value, Int32)]] = Map([])
  each(relation(input, env, ctx), ctx, row => {
    let values = keys.map(key => key_value(eval(key.1, row, ctx)))
    let id = @value.Value::from_list(values)
    let bucket = index.get_or_init(@value.group_key(id), () => [])
    let at = for entry in bucket {
      if @value.eqg(entry.0, id) {
        break entry.1
      }
    } nobreak {
      groups.push((values, []))
      bucket.push((id, groups.length() - 1))
      groups.length() - 1
    }
    let fields = members.map(name => (name, row.find(name).unwrap_or(Missing)))
    groups[at].1.push(@value.Value::from_tuple(@value.Tuple(fields)))
  })
  if grouping is All && groups.is_empty() {
    groups.push(([], []))
  }
  groups
  .map(g => {
    let mut bound = Frame(
      group_as,
      @value.Value::from_bag(@value.Bag(g.1)),
      env,
    )
    for i, key in keys {
      bound = Frame(key.0, g.0[i], bound)
    }
    bound
  })
  .iter()
}

///|
/// A SQL aggregate: `arg` for each member tuple of the group variable, with
/// `members` bound to the member's attributes on top of `env`, folded.
fn aggregate(
  kind : @plan.AggregateKind,
  distinct : Bool,
  arg : @plan.Expr,
  members : Array[String],
  group_name : String,
  env : Env,
  ctx : Ctx,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  guard env.find(group_name) is Some(Bag(tuples)) else {
    raise DataError(message="an aggregate function outside its group", span~)
  }
  let values = []
  for t in tuples.items() {
    let mut row = env
    for name in members {
      row = Frame(name, member_value(t, name), row)
    }
    values.push(eval(arg, row, ctx))
  }
  typed(ctx.mode, span, () => fold(kind, values.iter(), distinct))
}
