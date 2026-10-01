///|
fn num_of(v : Value) -> Num? {
  match v {
    Int(n) => Some(num_of_int64(n))
    BigInt(n) => Some(num_of_bigint(n))
    Float(d) => Some(num_of_double(d))
    Decimal(d) => Some(num_of_decimal(d))
    _ => None
  }
}

///|
fn lowered(v : Value) -> Value? {
  try v.lower() catch {
    _ => None
  } noraise {
    x => Some(x)
  }
}

///|
/// The spec's `=` for two non-absent, lowered values (spec 4.2 rule 3).
fn deep_equal(a : Value, b : Value) -> Bool {
  match (num_of(a), num_of(b)) {
    (Some(x), Some(y)) =>
      return !(x is NaN) && !(y is NaN) && compare_num(x, y) == 0
    (Some(_), None) | (None, Some(_)) => return false
    _ => ()
  }
  match (a, b) {
    (Bool(x), Bool(y)) => x == y
    (String(x), String(y)) => x == y
    (Clob(x) | Blob(x), Clob(y) | Blob(y)) => x == y
    (Date(x), Date(y)) => x == y
    (Time(x), Time(y)) =>
      match (x.offset, y.offset) {
        (Some(_), Some(_)) => x.utc_key() == y.utc_key()
        (None, None) => x.local_key() == y.local_key()
        _ => false
      }
    (Timestamp(x), Timestamp(y)) =>
      match (x.time.offset, y.time.offset) {
        (Some(_), Some(_)) => x.utc_key() == y.utc_key()
        (None, None) => x.local_key() == y.local_key()
        _ => false
      }
    (IntervalYM(x), IntervalYM(y)) => x == y
    (IntervalDT(x), IntervalDT(y)) => x == y
    (List(xs), List(ys)) =>
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(pair => eqg(pair.0, pair.1))
    (Bag(x), Bag(y)) => match_multiset(x.items(), y.items(), eqg)
    (Tuple(x), Tuple(y)) =>
      match_multiset(x.fields(), y.fields(), (p, q) => {
        p.0 == q.0 && eqg(p.1, q.1)
      })
    // Type parameters are ignored (RFC 0104 equality; Kotlin's comparator).
    (Map(x), Map(y)) =>
      match_multiset(x.entries(), y.entries(), (p, q) => {
        eqg(p.0, q.0) && eqg(p.1, q.1)
      })
    _ => false
  }
}

///|
/// The PartiQL `=` operator: MISSING if either side is MISSING, else NULL if
/// either side is NULL, else a Bool. Never fails on mixed types.
pub fn sql_equals(a : Value, b : Value) -> Value {
  match (lowered(a), lowered(b)) {
    (Some(x), Some(y)) =>
      match (x, y) {
        (Missing, _) | (_, Missing) => Missing
        (Null, _) | (_, Null) => Null
        _ => Bool(deep_equal(x, y))
      }
    _ => Bool(a == b)
  }
}

///|
/// Grouping equivalence: NULL eqg NULL, MISSING eqg MISSING, NaN eqg NaN;
/// otherwise the same as `=`.
pub fn eqg(a : Value, b : Value) -> Bool {
  match (lowered(a), lowered(b)) {
    (Some(x), Some(y)) =>
      match (x, y) {
        (Null, Null) | (Missing, Missing) => true
        (Null | Missing, _) | (_, Null | Missing) => false
        (Float(p), Float(q)) if p.is_nan() && q.is_nan() => true
        _ => deep_equal(x, y)
      }
    _ => a == b
  }
}
