///|
/// A PartiQL tuple: (name, value) pairs. Order is kept for output only;
/// duplicate names are allowed; no value is MISSING.
pub struct Tuple {
  priv fields : Array[(String, Value)]
}

///|
/// Builds a tuple. Pairs whose value is MISSING are dropped.
///
/// ```mbt check
/// test {
///   let tuple : @value.Tuple = @value.Tuple([
///     ("a", @value.Value::Missing),
///     ("b", @value.Value(2)),
///   ])
///   @expect.expect(tuple.get_all("b")).to_equal([@value.Value(2)])
/// }
/// ```
#alias(new, deprecated="Use Tuple(...) instead")
pub fn Tuple::Tuple(fields : Array[(String, Value)]) -> Tuple {
  { fields: fields.filter(pair => !(pair.1 is Missing)), }
}

///|
/// A read-only view of the retained fields, in input order. Duplicate names remain.
pub fn Tuple::fields(self : Tuple) -> ArrayView[(String, Value)] {
  self.fields[:]
}

///|
/// The number of retained name-value pairs, counting duplicate names.
pub fn Tuple::length(self : Tuple) -> Int32 {
  self.fields.length()
}

///|
/// The values of the attributes named `name` (case-sensitive).
pub fn Tuple::get_all(self : Tuple, name : String) -> Array[Value] {
  self.fields.filter(pair => pair.0 == name).map(pair => pair.1)
}
