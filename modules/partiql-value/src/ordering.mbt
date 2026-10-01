///|
/// Where NULL and MISSING sort.
pub(all) enum NullOrder {
  NullsFirst
  NullsLast
} derive(Debug, Eq)

///|
fn rank(v : Value) -> Int {
  match v {
    Null | Missing => 0
    Bool(_) => 1
    Int(_) | BigInt(_) | Float(_) | Decimal(_) => 2
    Date(_) => 3
    Time(_) => 4
    Timestamp(_) => 5
    IntervalYM(_) => 6
    IntervalDT(_) => 7
    String(_) => 8
    Clob(_) | Blob(_) => 9
    List(_) => 10
    Tuple(_) => 11
    Bag(_) => 12
    Ion(_) => 13 // never reached: values are lowered first
  }
}

///|
fn sign(n : Int) -> Int {
  if n < 0 {
    -1
  } else if n > 0 {
    1
  } else {
    0
  }
}

///|
fn compare_keys(a : (Int64, Int), b : (Int64, Int)) -> Int {
  let c = a.0.compare(b.0)
  if c != 0 {
    sign(c)
  } else {
    sign(a.1.compare(b.1))
  }
}

///|
/// Key and zone flag. The key is the UTC instant for a zoned value and the
/// fields for an unzoned one; at equal keys, an unzoned value sorts first.
/// (A tie-break on raw fields would not be transitive.)
fn compare_zoned(
  a_key : (Int64, Int),
  a_zoned : Bool,
  b_key : (Int64, Int),
  b_zoned : Bool,
) -> Int {
  let c = compare_keys(a_key, b_key)
  if c != 0 {
    c
  } else {
    sign(a_zoned.compare(b_zoned))
  }
}

///|
fn compare_lists(
  xs : ArrayView[Value],
  ys : ArrayView[Value],
  nulls : NullOrder,
) -> Int {
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for k in 0..<n {
    let c = compare(xs[k], ys[k], nulls~)
    if c != 0 {
      return c
    }
  }
  sign(xs.length().compare(ys.length()))
}

///|
fn sorted_values(values : ArrayView[Value], nulls : NullOrder) -> Array[Value] {
  let out = values.to_owned()
  out.sort_by((a, b) => compare(a, b, nulls~))
  out
}

///|
fn compare_pair(
  p : (String, Value),
  q : (String, Value),
  nulls : NullOrder,
) -> Int {
  let c = compare_text(p.0, q.0)
  if c != 0 {
    c
  } else {
    compare(p.1, q.1, nulls~)
  }
}

///|
fn compare_tuples(a : Tuple, b : Tuple, nulls : NullOrder) -> Int {
  let xs = a.fields().to_owned()
  let ys = b.fields().to_owned()
  xs.sort_by((p, q) => compare_pair(p, q, nulls))
  ys.sort_by((p, q) => compare_pair(p, q, nulls))
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for k in 0..<n {
    let c = compare_pair(xs[k], ys[k], nulls)
    if c != 0 {
      return c
    }
  }
  sign(xs.length().compare(ys.length()))
}

///|
fn lowered_or_self(v : Value) -> Value {
  try v.lower() catch {
    _ => v
  } noraise {
    x => x
  }
}

///|
/// The ORDER BY total order (spec section 4.4). Returns -1, 0 or 1.
pub fn compare(a : Value, b : Value, nulls~ : NullOrder) -> Int {
  let x = lowered_or_self(a)
  let y = lowered_or_self(b)
  let (rx, ry) = (rank(x), rank(y))
  if rx == 0 || ry == 0 {
    return match (rx == 0, ry == 0, nulls) {
      (true, true, _) => 0
      (true, false, NullsFirst) | (false, true, NullsLast) => -1
      _ => 1
    }
  }
  if rx != ry {
    return sign(rx.compare(ry))
  }
  match (x, y) {
    (Bool(p), Bool(q)) => sign(p.compare(q))
    (Date(p), Date(q)) =>
      compare_keys(
        (days_from_civil(p.year, p.month, p.day), 0),
        (days_from_civil(q.year, q.month, q.day), 0),
      )
    (Time(p), Time(q)) =>
      compare_zoned(
        if p.offset is Some(_) {
          p.utc_key()
        } else {
          p.local_key()
        },
        p.offset is Some(_),
        if q.offset is Some(_) {
          q.utc_key()
        } else {
          q.local_key()
        },
        q.offset is Some(_),
      )
    (Timestamp(p), Timestamp(q)) =>
      compare_zoned(
        if p.time.offset is Some(_) {
          p.utc_key()
        } else {
          p.local_key()
        },
        p.time.offset is Some(_),
        if q.time.offset is Some(_) {
          q.utc_key()
        } else {
          q.local_key()
        },
        q.time.offset is Some(_),
      )
    (IntervalYM(p), IntervalYM(q)) => sign(p.months.compare(q.months))
    (IntervalDT(p), IntervalDT(q)) =>
      compare_keys((p.seconds, p.nanos), (q.seconds, q.nanos))
    (String(p), String(q)) => compare_text(p, q)
    (Clob(p) | Blob(p), Clob(q) | Blob(q)) => compare_octets(p, q)
    (List(p), List(q)) => compare_lists(p[:], q[:], nulls)
    (Tuple(p), Tuple(q)) => compare_tuples(p, q, nulls)
    (Bag(p), Bag(q)) =>
      compare_lists(
        sorted_values(p.items(), nulls)[:],
        sorted_values(q.items(), nulls)[:],
        nulls,
      )
    _ =>
      match (num_of(x), num_of(y)) {
        (Some(m), Some(n)) => sign(compare_num(m, n))
        _ => 0
      }
  }
}
