///|
/// A PartiQL value.
///
/// `Ion` holds an exact Ion value (from a backtick literal or `$ion::`). It
/// is a representation, never a PartiQL type: every semantic acts on its
/// lowered value (see `Value::lower`).
/// Use `Value(x)` for `ToValue` conversions or explicit variants to choose
/// between representations such as Blob and Clob. Mutable arrays inside
/// list values are shared; copy them when independent storage is required.
pub(all) enum Value {
  /// The SQL null value.
  Null
  /// The absence of a value, for example a missing tuple attribute.
  Missing
  /// A boolean truth value.
  Bool(Bool)
  /// An integer that fits in Int64.
  Int(Int64)
  /// An integer outside the Int64 range. Build integers with
  /// `Value(n)` or `Value::integer`, which keep this invariant.
  BigInt(@bigint.BigInt)
  /// An IEEE binary64 value, including NaN, infinities and signed zero.
  Float(Double)
  /// A decimal with its scale.
  Decimal(@ion_core.Decimal)
  /// Unicode text.
  String(String)
  /// Character large-object bytes, distinct from a string or binary blob.
  Clob(Bytes)
  /// Binary large-object bytes.
  Blob(Bytes)
  /// A validated Gregorian date.
  Date(Date)
  /// A time of day with precision and an optional UTC offset.
  Time(Time)
  /// A date and time retaining precision and optional UTC offset.
  Timestamp(Timestamp)
  /// A signed count of calendar months.
  IntervalYM(IntervalYM)
  /// A signed duration at nanosecond resolution.
  IntervalDT(IntervalDT)
  /// An ordered collection; retains NULL, MISSING and duplicates.
  List(Array[Value])
  /// An unordered multiset; retains NULL, MISSING and duplicates.
  Bag(Bag)
  /// Named fields with duplicate names permitted and no MISSING values.
  Tuple(Tuple)
  /// A MAP (RFC 0104).
  Map(MapValue)
  /// A graph (RFC 0025).
  Graph(GraphValue)
  /// Exact Ion representation, including annotations and symbol metadata.
  Ion(@ion_core.IonValue)
}

///|
/// Whether the variant is `Null` or `Missing`, without lowering boxed Ion.
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
