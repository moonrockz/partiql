///|
/// A PartiQL tuple: (name, value) pairs. Order is kept for output only;
/// duplicate names are allowed; no value is MISSING.
pub struct Tuple {
  priv fields : Array[(String, Value)]
} derive(Debug)

///|
/// Builds a tuple. Pairs whose value is MISSING are dropped.
pub fn Tuple::new(fields : Array[(String, Value)]) -> Tuple {
  { fields: fields.filter(pair => !(pair.1 is Missing)), }
}

///|
pub fn Tuple::fields(self : Tuple) -> ArrayView[(String, Value)] {
  self.fields[:]
}

///|
pub fn Tuple::length(self : Tuple) -> Int {
  self.fields.length()
}

///|
/// The values of the attributes named `name` (case-sensitive).
pub fn Tuple::get_all(self : Tuple, name : String) -> Array[Value] {
  self.fields.filter(pair => pair.0 == name).map(pair => pair.1)
}
