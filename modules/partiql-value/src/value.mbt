///|
/// A PartiQL value.
///
/// M0 holds only the absent values. M1 adds scalars, tuples, lists and bags.
pub(all) enum Value {
  /// The SQL null value.
  Null
  /// The absence of a value, for example a missing tuple attribute.
  Missing
} derive(Debug, Eq)

///|
/// Whether the value is `NULL` or `MISSING`.
pub fn Value::is_absent(self : Value) -> Bool {
  match self {
    Null | Missing => true
  }
}
