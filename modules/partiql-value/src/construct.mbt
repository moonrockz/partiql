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
/// Use explicit variants for `Null`, `Missing` and ambiguous encodings such
/// as `Blob` versus `Clob`. Custom domain conversions implement `ToValue`.
/// Arrays convert recursively to lists. Bag, tuple, map, graph, datetime and
/// interval wrappers keep their kind. Ion values remain boxed, and an existing
/// `Value` passes through unchanged. Bytes have no implicit conversion.
/// Array conversion allocates a new list; other conversions do not copy
/// nested collection storage.
///
/// ```mbt check
/// test {
///   @expect.expect(@value.Value([1, 2])).to_equal(
///     @value.Value::List([Int(1), Int(2)]),
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
  Int(self.to_int64())
}

///|
pub impl ToValue for Int64 with fn to_value(self) {
  Int(self)
}

///|
pub impl ToValue for @bigint.BigInt with fn to_value(self) {
  Value::integer(self)
}

///|
pub impl ToValue for Bool with fn to_value(self) {
  Bool(self)
}

///|
pub impl ToValue for Double with fn to_value(self) {
  Float(self)
}

///|
pub impl ToValue for String with fn to_value(self) {
  String(self)
}

///|
pub impl ToValue for Value with fn to_value(self) {
  self
}

///|
pub impl ToValue for @ion_core.Decimal with fn to_value(self) {
  Decimal(self)
}

///|
pub impl ToValue for Date with fn to_value(self) {
  Date(self)
}

///|
pub impl ToValue for Time with fn to_value(self) {
  Time(self)
}

///|
pub impl ToValue for Timestamp with fn to_value(self) {
  Timestamp(self)
}

///|
pub impl ToValue for IntervalYM with fn to_value(self) {
  IntervalYM(self)
}

///|
pub impl ToValue for IntervalDT with fn to_value(self) {
  IntervalDT(self)
}

///|
pub impl ToValue for Bag with fn to_value(self) {
  Bag(self)
}

///|
pub impl ToValue for Tuple with fn to_value(self) {
  Value::from_tuple(self)
}

///|
pub impl ToValue for MapValue with fn to_value(self) {
  Map(self)
}

///|
pub impl ToValue for GraphValue with fn to_value(self) {
  Graph(self)
}

///|
pub impl ToValue for @ion_core.IonValue with fn to_value(self) {
  Ion(self)
}

///|
pub impl[T : ToValue] ToValue for Array[T] with fn to_value(self) {
  List(self.map(x => Value(x)))
}
