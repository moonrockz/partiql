///|
/// A PartiQL value.
///
/// `Ion` holds an exact Ion value (from a backtick literal or `$ion::`). It
/// is a representation, never a PartiQL type: every semantic acts on its
/// lowered value (see `Value::lower`).
pub(all) enum Value {
  /// The SQL null value.
  Null
  /// The absence of a value, for example a missing tuple attribute.
  Missing
  Bool(Bool)
  /// An integer that fits in Int64.
  Int(Int64)
  /// An integer outside the Int64 range. Build integers with
  /// `Value::integer`, which keeps this invariant.
  BigInt(@bigint.BigInt)
  Float(Double)
  /// A decimal with its scale.
  Decimal(@ion_core.Decimal)
  String(String)
  Clob(Bytes)
  Blob(Bytes)
  Date(Date)
  Time(Time)
  Timestamp(Timestamp)
  IntervalYM(IntervalYM)
  IntervalDT(IntervalDT)
  List(Array[Value])
  Bag(Bag)
  Tuple(Tuple)
  /// A MAP (RFC 0104).
  Map(MapValue)
  /// A graph (RFC 0025).
  Graph(GraphValue)
  Ion(@ion_core.IonValue)
} derive(Debug)

///|
/// Whether the value is `NULL` or `MISSING`.
pub fn Value::is_absent(self : Value) -> Bool {
  self is (Null | Missing)
}

///|
let int64_min : @bigint.BigInt = @bigint.BigInt::from_int64(
  -9223372036854775808L,
)

///|
let int64_max : @bigint.BigInt = @bigint.BigInt::from_int64(
  9223372036854775807L,
)

///|
/// An integer value: `Int` when it fits in Int64, else `BigInt`.
pub fn Value::integer(n : @bigint.BigInt) -> Value {
  if n.compare(int64_min) >= 0 && n.compare(int64_max) <= 0 {
    Int(n.to_int64())
  } else {
    BigInt(n)
  }
}
