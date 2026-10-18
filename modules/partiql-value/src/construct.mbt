///|
/// Conversion to a PartiQL value. Implement this trait for domain types that
/// have one unambiguous representation, then call `Value(x)`.
/// Conversions preserve types; they do not perform SQL CAST coercions.
pub(open) trait ToValue {
  /// Return the PartiQL representation without SQL coercion.
  fn to_value(Self) -> Value
}

///|
/// Convert a MoonBit value to its PartiQL representation.
/// Integers use `Int` when they fit in Int64 and `BigInt` otherwise.
/// Use `Null` and `Missing` directly, and choose `from_blob` or `from_clob`
/// explicitly for bytes. Custom domain conversions implement `ToValue`.
/// Typed `from_*` methods also supply expected types to nested constructors.
/// Arrays convert recursively to lists. Bag, tuple, map, graph, datetime and
/// interval wrappers keep their kind. Ion values remain boxed, and an existing
/// `Value` passes through unchanged. Bytes have no implicit conversion.
/// Array conversion allocates a new list; other conversions do not copy
/// nested collection storage.
///
/// ```mbt check
/// test {
///   @expect.expect(@value.Value([1, 2])).to_equal(
///     @value.Value::from_list([
///       @value.Value::from_int(1),
///       @value.Value::from_int(2),
///     ]),
///   )
/// }
/// ```
pub fn[T : ToValue] Value::Value(value : T) -> Value {
  ToValue::to_value(value)
}

///|
/// Wrap an existing tuple as a PartiQL value, preserving its fields and duplicates.
/// This is equivalent to `Value(tuple)` and does not rebuild the tuple.
/// The concrete parameter type disambiguates a nested `Tuple(...)` constructor.
///
/// ```mbt check
/// test {
///   let value = @value.Value::from_tuple(@value.Tuple([("a", @value.Value(1))]))
///   guard value is @value.Value::Tuple(tuple) else {
///     fail("expected a tuple value")
///   }
///   @expect.expect(tuple.get_all("a")).to_equal([@value.Value(1)])
/// }
/// ```
pub fn Value::from_tuple(tuple : Tuple) -> Value {
  Tuple(tuple)
}

///|
pub impl ToValue for Int32 with fn to_value(self) {
  Value::from_int(self.to_int64())
}

///|
pub impl ToValue for Int64 with fn to_value(self) {
  Value::from_int(self)
}

///|
pub impl ToValue for @bigint.BigInt with fn to_value(self) {
  Value::from_bigint(self)
}

///|
pub impl ToValue for Bool with fn to_value(self) {
  Value::from_bool(self)
}

///|
pub impl ToValue for Double with fn to_value(self) {
  Value::from_float(self)
}

///|
pub impl ToValue for String with fn to_value(self) {
  Value::from_string(self)
}

///|
pub impl ToValue for Value with fn to_value(self) {
  self
}

///|
pub impl ToValue for @ion_core.Decimal with fn to_value(self) {
  Value::from_decimal(self)
}

///|
pub impl ToValue for Date with fn to_value(self) {
  Value::from_date(self)
}

///|
pub impl ToValue for Time with fn to_value(self) {
  Value::from_time(self)
}

///|
pub impl ToValue for Timestamp with fn to_value(self) {
  Value::from_timestamp(self)
}

///|
pub impl ToValue for IntervalYM with fn to_value(self) {
  Value::from_interval_ym(self)
}

///|
pub impl ToValue for IntervalDT with fn to_value(self) {
  Value::from_interval_dt(self)
}

///|
pub impl ToValue for Bag with fn to_value(self) {
  Value::from_bag(self)
}

///|
pub impl ToValue for Tuple with fn to_value(self) {
  Value::from_tuple(self)
}

///|
pub impl ToValue for MapValue with fn to_value(self) {
  Value::from_map(self)
}

///|
pub impl ToValue for GraphValue with fn to_value(self) {
  Value::from_graph(self)
}

///|
pub impl ToValue for @ion_core.IonValue with fn to_value(self) {
  Value::from_ion(self)
}

///|
pub impl[T : ToValue] ToValue for Array[T] with fn to_value(self) {
  Value::from_list(self.map(x => Value(x)))
}

///|
/// Wrap a boolean as a PartiQL boolean.
pub fn Value::from_bool(value : Bool) -> Value {
  Bool(value)
}

///|
/// Wrap an Int64 as a PartiQL integer without changing its value.
pub fn Value::from_int(value : Int64) -> Value {
  Int(value)
}

///|
/// Normalize an arbitrary-precision integer: use Int when it fits Int64,
/// otherwise BigInt. Equivalent to the legacy `Value::integer` factory.
pub fn Value::from_bigint(value : @bigint.BigInt) -> Value {
  Value::integer(value)
}

///|
/// Wrap a binary64 number, retaining NaN, infinity and signed zero.
pub fn Value::from_float(value : Double) -> Value {
  Float(value)
}

///|
/// Wrap an Ion decimal without changing its coefficient, exponent or scale.
pub fn Value::from_decimal(value : @ion_core.Decimal) -> Value {
  Decimal(value)
}

///|
/// Wrap Unicode text as a PartiQL string.
pub fn Value::from_string(value : String) -> Value {
  String(value)
}

///|
/// Wrap bytes as a character large object. Distinct from `from_blob`.
/// The byte storage is shared; this conversion does not decode text.
pub fn Value::from_clob(value : Bytes) -> Value {
  Clob(value)
}

///|
/// Wrap bytes as a binary large object. Distinct from `from_clob`.
/// The byte storage is shared.
pub fn Value::from_blob(value : Bytes) -> Value {
  Blob(value)
}

///|
/// Wrap a validated Gregorian date without changing its calendar fields.
pub fn Value::from_date(value : Date) -> Value {
  Date(value)
}

///|
/// Wrap a validated time, retaining fractional precision and optional UTC offset.
pub fn Value::from_time(value : Time) -> Value {
  Time(value)
}

///|
/// Wrap a validated timestamp, retaining its date, time, precision and offset.
pub fn Value::from_timestamp(value : Timestamp) -> Value {
  Timestamp(value)
}

///|
/// Wrap a normalized year-month interval without changing its signed month count.
pub fn Value::from_interval_ym(value : IntervalYM) -> Value {
  IntervalYM(value)
}

///|
/// Wrap a normalized day-time interval without changing its seconds or nanoseconds.
pub fn Value::from_interval_dt(value : IntervalDT) -> Value {
  IntervalDT(value)
}

///|
/// Wrap an ordered list, retaining NULL, MISSING and duplicate elements.
/// The backing array is shared. Copy it first if independent storage is required.
/// Unlike generic `Value(array)`, this conversion does not map or copy elements.
pub fn Value::from_list(value : Array[Value]) -> Value {
  List(value)
}

///|
/// Wrap an existing bag without rebuilding it; retain duplicates and absent values.
/// The concrete parameter type disambiguates a nested `Bag(...)` constructor.
pub fn Value::from_bag(value : Bag) -> Value {
  Bag(value)
}

///|
/// Wrap a validated map without rebuilding entries or changing declared types.
pub fn Value::from_map(value : MapValue) -> Value {
  Map(value)
}

///|
/// Wrap a validated graph without rebuilding nodes, edges or payloads.
pub fn Value::from_graph(value : GraphValue) -> Value {
  Graph(value)
}

///|
/// Box exact Ion, retaining annotations, symbols and representation details.
/// This does not lower Ion or decode PartiQL annotations; use the Ion codec
/// package's `from_ion` to decode PartiQL-encoded Ion instead.
pub fn Value::from_ion(value : @ion_core.IonValue) -> Value {
  Ion(value)
}
