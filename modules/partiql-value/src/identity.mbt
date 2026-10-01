///|
fn same_decimal(a : @ion_core.Decimal, b : @ion_core.Decimal) -> Bool {
  a.coefficient == b.coefficient &&
  a.exponent == b.exponent &&
  a.negative_zero == b.negative_zero
}

///|
fn same_float(a : Double, b : Double) -> Bool {
  (a.is_nan() && b.is_nan()) ||
  a.reinterpret_as_uint64() == b.reinterpret_as_uint64()
}

///|
pub impl Eq for Date with fn equal(a, b) {
  a.year == b.year && a.month == b.month && a.day == b.day
}

///|
pub impl Eq for Time with fn equal(a, b) {
  a.hour == b.hour &&
  a.minute == b.minute &&
  a.second == b.second &&
  a.nanos == b.nanos &&
  a.precision == b.precision &&
  a.offset == b.offset
}

///|
pub impl Eq for Timestamp with fn equal(a, b) {
  a.date == b.date && a.time == b.time
}

///|
pub impl Eq for IntervalYM with fn equal(a, b) {
  a.months == b.months
}

///|
pub impl Eq for IntervalDT with fn equal(a, b) {
  a.seconds == b.seconds && a.nanos == b.nanos
}

///|
pub impl Eq for Tuple with fn equal(a, b) {
  match_multiset(a.fields[:], b.fields[:], (x, y) => x.0 == y.0 && x.1 == y.1)
}

///|
pub impl Eq for Bag with fn equal(a, b) {
  match_multiset(a.items[:], b.items[:], (x, y) => x == y)
}

///|
pub impl Eq for MapValue with fn equal(a, b) {
  a.key_type == b.key_type &&
  a.value_type == b.value_type &&
  match_multiset(a.entries[:], b.entries[:], (x, y) => x.0 == y.0 && x.1 == y.1)
}

///|
pub impl Eq for Ends with fn equal(a, b) {
  match (a, b) {
    (Directed(from=f1, to=t1), Directed(from=f2, to=t2)) => f1 == f2 && t1 == t2
    (Undirected(a1, b1), Undirected(a2, b2)) =>
      (a1 == a2 && b1 == b2) || (a1 == b2 && b1 == a2)
    _ => false
  }
}

///|
pub impl Eq for GraphValue with fn equal(a, b) {
  same_graph(a, b, (x, y) => x == y)
}

///|
/// Structural identity (spec section 4.1).
pub impl Eq for Value with fn equal(a, b) {
  match (a, b) {
    (Null, Null) | (Missing, Missing) => true
    (Bool(x), Bool(y)) => x == y
    (Int(x), Int(y)) => x == y
    (BigInt(x), BigInt(y)) => x == y
    (Float(x), Float(y)) => same_float(x, y)
    (Decimal(x), Decimal(y)) => same_decimal(x, y)
    (String(x), String(y)) => x == y
    (Clob(x), Clob(y)) | (Blob(x), Blob(y)) => x == y
    (Date(x), Date(y)) => x == y
    (Time(x), Time(y)) => x == y
    (Timestamp(x), Timestamp(y)) => x == y
    (IntervalYM(x), IntervalYM(y)) => x == y
    (IntervalDT(x), IntervalDT(y)) => x == y
    (List(xs), List(ys)) =>
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(pair => pair.0 == pair.1)
    (Bag(x), Bag(y)) => x == y
    (Tuple(x), Tuple(y)) => x == y
    (Map(x), Map(y)) => x == y
    (Graph(x), Graph(y)) => x == y
    (Ion(x), Ion(y)) => x.equals(y)
    _ => false
  }
}
