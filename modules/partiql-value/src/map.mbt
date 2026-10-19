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
}

///|
/// Whether a map with this key type can hold `key` (RFC 0104): the key is of
/// the same type family. Every number fits a numeric key type, and every
/// string a character key type. DYNAMIC holds no key (RFC 0104 leaves it for
/// future work), and NULL, MISSING and non-scalar values are never keys.
pub fn MapType::admits(self : MapType, key : Value) -> Bool {
  match (self, key) {
    (
      TinyInt
      | SmallInt
      | Integer
      | BigInt
      | Numeric
      | Decimal
      | Real
      | Double,
      Int(_)
      | BigInt(_)
      | Decimal(_)
      | Float(_),
    ) => true
    (String | Char | Varchar, String(_)) => true
    (Bool, Bool(_)) | (Date, Date(_)) | (Time, Time(_)) => true
    (Timestamp, Timestamp(_)) => true
    _ => false
  }
}

///|
/// Builds a MAP. Entries whose value is MISSING are dropped (RFC 0104).
/// Keys are lowered first; NULL, MISSING and non-scalar keys, and keys equal
/// under `eqg` to an earlier key, raise.
#alias(new, deprecated="Use MapValue(...) instead")
pub fn MapValue::MapValue(
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
    if !key_type.admits(key) {
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
/// A read-only view of the retained entries in insertion order. Keys are lowered
/// and entries with MISSING values have already been removed.
pub fn MapValue::entries(self : MapValue) -> ArrayView[(Value, Value)] {
  self.entries[:]
}

///|
/// The number of retained entries after dropping MISSING values.
pub fn MapValue::length(self : MapValue) -> Int32 {
  self.entries.length()
}
