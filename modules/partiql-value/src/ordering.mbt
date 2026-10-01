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
    Map(_) => 13
    Graph(_) => 14
    // Only an Ion value that cannot be lowered (a symbol without text)
    // keeps this rank; such values compare equal to each other.
    Ion(_) => 15
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
fn compare_entry(
  p : (Value, Value),
  q : (Value, Value),
  nulls : NullOrder,
) -> Int {
  let c = compare(p.0, q.0, nulls~)
  if c != 0 {
    c
  } else {
    compare(p.1, q.1, nulls~)
  }
}

///|
/// RFC 0104: sort each map's entries by key then value, then compare
/// lexicographically (a shorter prefix first).
fn compare_maps(a : MapValue, b : MapValue, nulls : NullOrder) -> Int {
  let xs = a.entries().to_owned()
  let ys = b.entries().to_owned()
  xs.sort_by((p, q) => compare_entry(p, q, nulls))
  ys.sort_by((p, q) => compare_entry(p, q, nulls))
  let n = if xs.length() < ys.length() { xs.length() } else { ys.length() }
  for k in 0..<n {
    let c = compare_entry(xs[k], ys[k], nulls)
    if c != 0 {
      return c
    }
  }
  sign(xs.length().compare(ys.length()))
}

///|
fn compare_text_lists(a : Array[String], b : Array[String]) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for k in 0..<n {
    let c = compare_text(a[k], b[k])
    if c != 0 {
      return c
    }
  }
  sign(a.length().compare(b.length()))
}

///|
fn sorted_labels(labels : Array[String]) -> Array[String] {
  let out = labels.copy()
  out.sort_by(compare_text)
  out
}

///|
/// An absent payload sorts before any payload.
fn compare_payloads(a : Value?, b : Value?, nulls : NullOrder) -> Int {
  match (a, b) {
    (None, None) => 0
    (None, Some(_)) => -1
    (Some(_), None) => 1
    (Some(x), Some(y)) => compare(x, y, nulls~)
  }
}

///|
/// Directed before undirected; directed by (from, to), undirected by its
/// sorted pair of node ids.
fn compare_ends(a : Ends, b : Ends) -> Int {
  let key = (e : Ends) => {
    match e {
      Directed(from~, to~) => (0, from, to)
      Undirected(x, y) =>
        if compare_text(x, y) <= 0 {
          (1, x, y)
        } else {
          (1, y, x)
        }
    }
  }
  let (ka, kb) = (key(a), key(b))
  let c = sign(ka.0.compare(kb.0))
  if c != 0 {
    return c
  }
  let c2 = compare_text(ka.1, kb.1)
  if c2 != 0 {
    c2
  } else {
    compare_text(ka.2, kb.2)
  }
}

///|
fn compare_nodes(a : GraphNode, b : GraphNode, nulls : NullOrder) -> Int {
  let c = compare_text(a.id, b.id)
  if c != 0 {
    return c
  }
  let c2 = compare_text_lists(sorted_labels(a.labels), sorted_labels(b.labels))
  if c2 != 0 {
    return c2
  }
  compare_payloads(a.payload, b.payload, nulls)
}

///|
fn compare_edges(a : GraphEdge, b : GraphEdge, nulls : NullOrder) -> Int {
  let c = compare_text(a.id, b.id)
  if c != 0 {
    return c
  }
  let c2 = compare_text_lists(sorted_labels(a.labels), sorted_labels(b.labels))
  if c2 != 0 {
    return c2
  }
  let c3 = compare_ends(a.ends, b.ends)
  if c3 != 0 {
    return c3
  }
  compare_payloads(a.payload, b.payload, nulls)
}

///|
/// Compares canonical forms: nodes sorted by id, then edges sorted by id,
/// each list lexicographic with a shorter prefix first.
fn compare_graphs(a : GraphValue, b : GraphValue, nulls : NullOrder) -> Int {
  let by_id_n = (x : GraphNode, y : GraphNode) => compare_text(x.id, y.id)
  let by_id_e = (x : GraphEdge, y : GraphEdge) => compare_text(x.id, y.id)
  let an = a.nodes().to_owned()
  let bn = b.nodes().to_owned()
  an.sort_by(by_id_n)
  bn.sort_by(by_id_n)
  let n = if an.length() < bn.length() { an.length() } else { bn.length() }
  for k in 0..<n {
    let c = compare_nodes(an[k], bn[k], nulls)
    if c != 0 {
      return c
    }
  }
  let c = sign(an.length().compare(bn.length()))
  if c != 0 {
    return c
  }
  let ae = a.edges().to_owned()
  let be = b.edges().to_owned()
  ae.sort_by(by_id_e)
  be.sort_by(by_id_e)
  let m = if ae.length() < be.length() { ae.length() } else { be.length() }
  for k in 0..<m {
    let c = compare_edges(ae[k], be[k], nulls)
    if c != 0 {
      return c
    }
  }
  sign(ae.length().compare(be.length()))
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
    (Map(p), Map(q)) => compare_maps(p, q, nulls)
    (Graph(p), Graph(q)) => compare_graphs(p, q, nulls)
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
