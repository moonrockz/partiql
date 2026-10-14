// ORDER BY: a query's output elements, sorted (spec M4b2 §3). Each element
// keeps the binding tuple its sort keys run in: for a SELECT body, the row
// of the FROM and LET variables with the output names on top; for any other
// body, the outer binding tuple with the element in `@plan.row_variable`.

///|
/// A query with ORDER BY: the elements of its body, sorted, as a list.
fn query(
  e : @plan.Expr,
  env : Env,
  ctx : Ctx,
) -> @value.Value raise @plan.EvalError {
  guard e is Query(body, order~, limit=_, offset=_, aliases~, _) else {
    return eval(e, env, ctx)
  }
  let pairs = match body {
    Select(rel, projection, distinct~, _) =>
      select_pairs(rel, projection, distinct, env, ctx).map(pair => {
        let (row, v) = pair
        let keys_env = aliases.fold(init=row, (acc, name) => {
          Frame(name, output_attribute(v, name), acc)
        })
        (keys_env, v)
      })
    _ =>
      elements(eval(body, env, ctx)).map(v => {
        (Frame(@plan.row_variable, v, env), v)
      })
  }
  List(sorted(pairs, order, ctx))
}

///|
/// The value of the first attribute of a projected tuple called exactly
/// `name`, else MISSING.
fn output_attribute(v : @value.Value, name : String) -> @value.Value {
  match v {
    Tuple(t) =>
      for field in t.fields() {
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
/// The output elements of a value: the items of a list or a bag, else the
/// value itself.
fn elements(v : @value.Value) -> Array[@value.Value] {
  match unboxed(v) {
    List(items) => items
    Bag(b) => b.items().to_owned()
    other => [other]
  }
}

///|
/// The values of `pairs`, sorted by the keys of `order`, each evaluated once
/// in the binding tuple of its pair. Ties keep their input order (plan
/// ruling 2): the sort compares input positions last, so it does not depend
/// on the stability of the core sort. A key that fails raises in strict
/// mode; in permissive mode `eval` has made it MISSING.
fn sorted(
  pairs : Array[(Env, @value.Value)],
  order : Array[@plan.SortKey],
  ctx : Ctx,
) -> Array[@value.Value] raise @plan.EvalError {
  let keys = []
  for pair in pairs {
    keys.push(order.map(key => eval(key.expr, pair.0, ctx)))
  }
  let positions = Array::makei(pairs.length(), i => i)
  positions.sort_by((i, j) => {
    for k, key in order {
      let c = compare_key(keys[i][k], keys[j][k], key)
      if c != 0 {
        break c
      }
    } nobreak {
      i.compare(j)
    }
  })
  positions.map(i => pairs[i].1)
}

///|
/// The order of two key values (plan ruling 1): ASC is the total order with
/// NULL and MISSING placed by `nulls_first`; DESC is the reverse of the
/// ascending order with the opposite placement, so absent values, also nested
/// ones, end up where `nulls_first` says.
fn compare_key(
  a : @value.Value,
  b : @value.Value,
  key : @plan.SortKey,
) -> Int32 {
  let first : @value.NullOrder = NullsFirst
  let last : @value.NullOrder = NullsLast
  if key.desc {
    -@value.compare(a, b, nulls=if key.nulls_first { last } else { first })
  } else {
    @value.compare(a, b, nulls=if key.nulls_first { first } else { last })
  }
}
