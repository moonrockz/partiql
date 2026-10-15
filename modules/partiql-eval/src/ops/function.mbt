// The shared argument rule of the built-in functions (spec M4d1 §4).

///|
/// The values a built-in function accepts at one argument position. NULL and
/// MISSING are handled by `apply`, never by a `Param`.
priv enum Param {
  /// A character string (an Ion symbol is a string after unboxing).
  Text
  /// A character or binary string: String, Blob or Clob.
  Bytes
  /// A list, bag, tuple or map.
  Collection
  Tuple
  Map
  /// Any value (a map key; the map decides compatibility).
  Any
  /// An integer or a decimal with scale 0 (SQL MOD: exact numeric, scale 0).
  Exact
  /// A number or an interval (ABS).
  Numeric
  /// An integer: Int or BigInt.
  Integer
}

///|
fn Param::accepts(self : Param, v : @value.Value) -> Bool {
  match (self, v) {
    (Text, String(_)) => true
    (Bytes, String(_) | Blob(_) | Clob(_)) => true
    (Collection, List(_) | Bag(_) | Tuple(_) | Map(_)) => true
    (Tuple, Tuple(_)) => true
    (Map, Map(_)) => true
    (Any, _) => true
    (Exact, Int(_) | BigInt(_)) => true
    (Exact, Decimal(d)) => d.exponent() == 0
    (Numeric, Int(_) | BigInt(_) | Decimal(_) | Float(_)) => true
    (Numeric, IntervalYM(_) | IntervalDT(_)) => true
    (Integer, Int(_) | BigInt(_)) => true
    _ => false
  }
}

///|
/// Runs a built-in on its arguments (spec M4d1 §4.3; partiql-tests
/// mod.ion:159-204, substring.ion:974, position.ion:110): unbox the Ion
/// values; a non-absent argument of a type its parameter does not accept is
/// a `TypeFailure`, also when another argument is MISSING or NULL; then any
/// MISSING gives MISSING; then any NULL gives NULL; else `compute`.
fn apply(
  name : String,
  params : Array[Param],
  args : Array[@value.Value],
  compute : (Array[@value.Value]) -> @value.Value raise OpFailure,
) -> @value.Value raise OpFailure {
  guard params.length() == args.length() else {
    raise DataFailure("\{name} got \{args.length()} arguments")
  }
  let values : Array[@value.Value] = []
  for arg in args {
    values.push(boxed(arg))
  }
  for i, v in values {
    if !v.is_absent() && !params[i].accepts(v) {
      raise TypeFailure("argument \{i + 1} of \{name} has the wrong type")
    }
  }
  if values.iter().any(v => v is Missing) {
    return Missing
  }
  if values.iter().any(v => v is Null) {
    return Null
  }
  compute(values)
}
