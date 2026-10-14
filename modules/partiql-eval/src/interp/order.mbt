// ORDER BY: a query's output elements, sorted (spec M4b2 §3). Each element
// keeps the binding tuple its sort keys run in: for a SELECT body, the row
// of the FROM and LET variables with the output names on top; for any other
// body, the outer binding tuple with the element in `@plan.row_variable`.

///|
/// How many rows a LIMIT or OFFSET clause names. A value beyond Int64 is
/// `Unbounded`: as an OFFSET it skips every row, as a LIMIT it keeps all.
priv enum Count {
  Upto(Int64)
  Unbounded
}

///|
/// The count of a LIMIT or OFFSET clause, evaluated once in `env` (plan
/// ruling 3). No clause, and in permissive mode a value that is not an
/// integer of at least 0, put no restriction (`None`); in strict mode such a
/// value is a `TypeError`.
fn clause_count(
  clause : @plan.Expr?,
  name : String,
  env : Env,
  ctx : Ctx,
) -> Count? raise @plan.EvalError {
  guard clause is Some(e) else { return None }
  match unboxed(eval(e, env, ctx)) {
    Int(n) if n >= 0L => Some(Upto(n))
    BigInt(n) if n >= 0N => Some(Unbounded)
    _ =>
      match ctx.mode {
        Permissive => None
        Strict =>
          raise TypeError(
            message="\{name} must be a non-negative integer",
            span=e.span(),
          )
      }
  }
}

///|
/// How many rows of a SELECT body a reader needs to pull to fill the window
/// of `offset` and `limit`: all (`None`) if the limit is unbounded or absent.
fn rows_needed(offset : Count?, limit : Count?) -> Int64? {
  match (offset, limit) {
    (_, Some(Upto(n))) =>
      match offset {
        None => Some(n)
        Some(Upto(k)) if k <= 9223372036854775807L - n => Some(k + n)
        _ => None
      }
    _ => None
  }
}

///|
/// The window of `items` after `offset` rows and up to `limit` rows.
fn[T] window(items : Array[T], offset : Count?, limit : Count?) -> Array[T] {
  let len = items.length().to_int64()
  let start = match offset {
    None => 0L
    Some(Upto(n)) => if n < len { n } else { len }
    Some(Unbounded) => len
  }
  let take = match limit {
    Some(Upto(n)) => if n < len - start { n } else { len - start }
    _ => len - start
  }
  if start == 0L && take == len {
    return items
  }
  items[start.to_int():(start + take).to_int()].to_owned()
}

///|
/// A query with ORDER BY, LIMIT or OFFSET: the elements of its body, sorted
/// (a list), or only cut to the window (a bag). LIMIT and OFFSET are
/// evaluated once, in the outer binding tuple, before the body. Without
/// ORDER BY a SELECT body is read only as far as the window needs.
fn query(
  e : @plan.Expr,
  env : Env,
  ctx : Ctx,
) -> @value.Value raise @plan.EvalError {
  guard e is Query(body, order~, limit~, offset~, aliases~, _) else {
    return eval(e, env, ctx)
  }
  let offset = clause_count(offset, "OFFSET", env, ctx)
  let limit = clause_count(limit, "LIMIT", env, ctx)
  let pairs = match body {
    Select(rel, projection, distinct~, _) => {
      let upto = if order.is_empty() {
        rows_needed(offset, limit)
      } else {
        None
      }
      select_pairs_upto(rel, projection, distinct, env, ctx, upto).map(pair => {
        let (row, v) = pair
        // Only a sort key reads the output names.
        if order.is_empty() {
          (row, v)
        } else {
          let keys_env = aliases.fold(init=row, (acc, name) => {
            Frame(@plan.output_variable(name), output_attribute(v, name), acc)
          })
          (keys_env, v)
        }
      })
    }
    _ =>
      elements(eval(body, env, ctx)).map(v => {
        (Frame(@plan.row_variable, v, env), v)
      })
  }
  if body is Select(_, Pivot(..), distinct=_, _) {
    // ORDER BY, LIMIT and OFFSET cut the rows; PIVOT then joins what is left.
    let rows = if order.is_empty() {
      window(pairs.map(pair => pair.1), offset, limit)
    } else {
      window(sorted(pairs, order, ctx), offset, limit)
    }
    return pivoted(rows)
  }
  if order.is_empty() {
    Bag(@value.Bag::new(window(pairs.map(pair => pair.1), offset, limit)))
  } else {
    List(window(sorted(pairs, order, ctx), offset, limit))
  }
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
