// CAST (spec M4d2).

///|
/// The width of an integer target: TINYINT, SMALLINT, INT, BIGINT.
pub(all) enum IntWidth {
  Bits8
  Bits16
  Bits32
  Bits64
} derive(Eq, Debug)

///|
/// REAL (binary32) or DOUBLE PRECISION (binary64).
pub(all) enum FloatWidth {
  Real
  Double
} derive(Eq, Debug)

///|
/// The scale of a DECIMAL target: a bare DECIMAL keeps the scale of the
/// value (rounded to 38 digits); DECIMAL(p, s) has scale s.
pub(all) enum Scale {
  Unconstrained
  Fixed(precision~ : Int32, scale~ : Int32)
} derive(Eq, Debug)

///|
/// A character string target. Lengths are in code points.
pub(all) enum TextKind {
  Char(Int32)
  Varchar(Int32)
  String
} derive(Eq, Debug)

///|
/// The target of a CAST, resolved by lowering (spec M4d2 §3.1). `Map` keeps
/// the targets of its keys and values and the declared map types, because a
/// target cannot tell NUMERIC from DECIMAL and a `MapType` can.
pub(all) enum CastTarget {
  Any
  Bool
  Integer(IntWidth)
  Decimal(Scale)
  Float(FloatWidth)
  Text(TextKind)
  Clob
  Blob
  Date
  Time(precision~ : Int32?, zone~ : Bool)
  Timestamp(precision~ : Int32?, zone~ : Bool)
  Interval(@ast.IntervalQualifier)
  List
  Bag
  Tuple
  Map(
    key~ : CastTarget,
    key_type~ : @value.MapType,
    value~ : CastTarget,
    value_type~ : @value.MapType
  )
} derive(Eq, Debug)

///|
/// The SQL name of a value's kind, for messages.
fn kind_name(x : @value.Value) -> String {
  match x {
    Null => "NULL"
    Missing => "MISSING"
    Bool(_) => "BOOL"
    Int(_) | BigInt(_) => "INT"
    Float(_) => "FLOAT"
    Decimal(_) => "DECIMAL"
    String(_) => "STRING"
    Clob(_) => "CLOB"
    Blob(_) => "BLOB"
    Date(_) => "DATE"
    Time(_) => "TIME"
    Timestamp(_) => "TIMESTAMP"
    IntervalYM(_) | IntervalDT(_) => "INTERVAL"
    List(_) => "LIST"
    Bag(_) => "BAG"
    Tuple(_) => "TUPLE"
    Map(_) => "MAP"
    Graph(_) => "GRAPH"
    Ion(_) => "ION"
  }
}

///|
/// The SQL name of a target, for messages.
fn target_name(t : CastTarget) -> String {
  match t {
    Any => "ANY"
    Bool => "BOOL"
    Integer(Bits8) => "TINYINT"
    Integer(Bits16) => "SMALLINT"
    Integer(Bits32) => "INT"
    Integer(Bits64) => "BIGINT"
    Decimal(Unconstrained) => "DECIMAL"
    Decimal(Fixed(precision~, scale~)) => "DECIMAL(\{precision},\{scale})"
    Float(Real) => "REAL"
    Float(Double) => "DOUBLE PRECISION"
    Text(Char(n)) => "CHAR(\{n})"
    Text(Varchar(n)) => "VARCHAR(\{n})"
    Text(String) => "STRING"
    Clob => "CLOB"
    Blob => "BLOB"
    Date => "DATE"
    Time(zone~, ..) => if zone { "TIME WITH TIME ZONE" } else { "TIME" }
    Timestamp(zone~, ..) =>
      if zone {
        "TIMESTAMP WITH TIME ZONE"
      } else {
        "TIMESTAMP"
      }
    Interval(_) => "INTERVAL"
    List => "LIST"
    Bag => "BAG"
    Tuple => "TUPLE"
    Map(..) => "MAP"
  }
}

///|
/// `CAST(v AS target)` (spec M4d2 §4.2): an Ion value is unboxed; NULL and
/// MISSING stay as they are; ANY gives the operand; then the target group
/// decides by the kind of the value.
pub fn cast(
  v : @value.Value,
  target : CastTarget,
) -> @value.Value raise OpFailure {
  let x = boxed(v)
  if x is (Null | Missing) {
    return x
  }
  match target {
    Any => v
    Bool => to_bool(x)
    Integer(width) => to_integer(x, width)
    Decimal(scale) => to_decimal_target(x, scale)
    Float(width) => to_float_target(x, width)
    Text(kind) => to_text(x, kind)
    Clob | Blob => to_lob(x, target)
    _ =>
      raise Unsupported("CAST to \{target_name(target)} is not supported yet")
  }
}
