///|
/// The declared key or value type of a MAP (RFC 0104). The names are the
/// static type names of partiql-tests' `$map::<key>::<value>::` encoding.
pub(all) enum MapType {
  Dynamic
  Bool
  TinyInt
  SmallInt
  Integer
  BigInt
  Numeric
  Decimal
  Real
  Double
  String
  Char
  Varchar
  Date
  Time
  Timestamp
} derive(Debug, Eq)

///|
/// The type name as partiql-tests writes it.
pub fn MapType::name(self : MapType) -> String {
  match self {
    Dynamic => "dynamic"
    Bool => "bool"
    TinyInt => "tinyint"
    SmallInt => "smallint"
    Integer => "integer"
    BigInt => "bigint"
    Numeric => "numeric"
    Decimal => "decimal"
    Real => "real"
    Double => "double"
    String => "string"
    Char => "char"
    Varchar => "varchar"
    Date => "date"
    Time => "time"
    Timestamp => "timestamp"
  }
}

///|
/// The type for a name; `int` is accepted for `integer`.
pub fn MapType::from_name(name : String) -> MapType? {
  match name {
    "dynamic" => Some(Dynamic)
    "bool" => Some(Bool)
    "tinyint" => Some(TinyInt)
    "smallint" => Some(SmallInt)
    "integer" | "int" => Some(Integer)
    "bigint" => Some(BigInt)
    "numeric" => Some(Numeric)
    "decimal" => Some(Decimal)
    "real" => Some(Real)
    "double" => Some(Double)
    "string" => Some(String)
    "char" => Some(Char)
    "varchar" => Some(Varchar)
    "date" => Some(Date)
    "time" => Some(Time)
    "timestamp" => Some(Timestamp)
    _ => None
  }
}

///|
/// Why a MAP could not be built.
pub(all) suberror MapError {
  /// A NULL, MISSING, non-scalar or unlowerable key.
  InvalidKey(String)
  /// Two keys that are equal under `eqg`.
  DuplicateKey(String)
  /// RFC 0104 leaves a DYNAMIC key type for future work.
  DynamicKeyType
} derive(Debug, Eq)

///|
/// A PartiQL MAP: unique scalar keys, no MISSING values. The stored order
/// is the insertion order (for output); equality and ordering ignore it.
pub struct MapValue {
  key_type : MapType
  value_type : MapType
  priv entries : Array[(Value, Value)]
} derive(Debug)

///|
fn is_scalar_key(key : Value) -> Bool {
  key
  is (Bool(_)
  | Int(_)
  | BigInt(_)
  | Float(_)
  | Decimal(_)
  | String(_)
  | Clob(_)
  | Blob(_)
  | Date(_)
  | Time(_)
  | Timestamp(_)
  | IntervalYM(_)
  | IntervalDT(_))
}

///|
/// Builds a MAP. Entries whose value is MISSING are dropped (RFC 0104).
/// Keys are lowered first; NULL, MISSING and non-scalar keys, and keys equal
/// under `eqg` to an earlier key, raise.
pub fn MapValue::new(
  key_type~ : MapType,
  value_type~ : MapType,
  entries : Array[(Value, Value)],
) -> MapValue raise MapError {
  if key_type == Dynamic {
    raise DynamicKeyType
  }
  // Validate every key first, also those whose value is MISSING: a strict
  // constructor rejects an invalid or duplicate key in any entry.
  let keys : Array[Value] = []
  for entry in entries {
    let key = entry.0.lower() catch {
      _ => raise InvalidKey("a symbol without text")
    }
    if !is_scalar_key(key) {
      raise InvalidKey(@debug.to_string(key))
    }
    if keys.iter().any(k => eqg(k, key)) {
      raise DuplicateKey(@debug.to_string(key))
    }
    keys.push(key)
  }
  let kept : Array[(Value, Value)] = []
  for k, entry in entries {
    if !(entry.1 is Missing) {
      kept.push((keys[k], entry.1))
    }
  }
  { key_type, value_type, entries: kept, }
}

///|
pub fn MapValue::entries(self : MapValue) -> ArrayView[(Value, Value)] {
  self.entries[:]
}

///|
pub fn MapValue::length(self : MapValue) -> Int {
  self.entries.length()
}
