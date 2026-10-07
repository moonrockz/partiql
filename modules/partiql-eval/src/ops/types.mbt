///|
fn in_range(v : @value.Value, low : Int64, high : Int64) -> Bool {
  match v {
    Int(n) => n >= low && n <= high
    _ => false
  }
}

///|
/// The digits left of the point of a decimal, and its scale. Int64: `-e`
/// must not overflow for the Int minimum.
fn decimal_shape(d : @ion_core.Decimal) -> (Int64, Int64) {
  let digits = if d.coefficient().is_zero() {
    0L
  } else {
    digit_count(d.coefficient()).to_int64()
  }
  let scale = (-d.exponent().to_int64()).max(0L)
  ((digits - scale).max(0L), scale)
}

///|
/// Whether a decimal fits DECIMAL(p, s): no more fraction digits than `s` and
/// no more integer digits than `p - s`. A bare DECIMAL takes any decimal.
fn decimal_fits(d : @ion_core.Decimal, precision : Int?, scale : Int?) -> Bool {
  match precision {
    None => true
    Some(p) => {
      let s = scale.unwrap_or(0).to_int64()
      let (whole, fraction) = decimal_shape(d)
      fraction <= s && whole <= p.to_int64() - s
    }
  }
}

///|
fn map_type_of(t : @ast.DataType) -> @value.MapType? {
  match t {
    Bool => Some(@value.MapType::Bool)
    TinyInt => Some(@value.MapType::TinyInt)
    SmallInt => Some(@value.MapType::SmallInt)
    Int => Some(@value.MapType::Integer)
    BigInt => Some(@value.MapType::BigInt)
    Numeric(_, _) => Some(@value.MapType::Numeric)
    Decimal(_, _) => Some(@value.MapType::Decimal)
    Real => Some(@value.MapType::Real)
    Double(_) => Some(@value.MapType::Double)
    String => Some(@value.MapType::String)
    Char(_) => Some(@value.MapType::Char)
    Varchar(_) => Some(@value.MapType::Varchar)
    Date => Some(@value.MapType::Date)
    Time(_, ..) => Some(@value.MapType::Time)
    Timestamp(_, ..) => Some(@value.MapType::Timestamp)
    _ => None
  }
}

///|
/// `v IS type`. A value of another type, also NULL, is FALSE; for a MAP type
/// NULL gives NULL and MISSING gives MISSING (partiql-tests map.ion).
pub fn is_type(
  v : @value.Value,
  t : @ast.DataType,
) -> @value.Value raise OpFailure {
  let x = boxed(v)
  if t is @ast.DataType::Map(_, _) && x is (Null | Missing) {
    return x
  }
  let holds = match t {
    Null => x is Null
    Missing => x is Missing
    Any => !(x is Missing)
    Bool => x is Bool(_)
    TinyInt => in_range(x, -128L, 127L)
    SmallInt => in_range(x, -32768L, 32767L)
    Int => in_range(x, -2147483648L, 2147483647L)
    // BIGINT is the Int64 range, as in arithmetic; a `BigInt` value is wider.
    BigInt => x is Int(_)
    Decimal(p, s) | Numeric(p, s) =>
      match x {
        Decimal(d) => decimal_fits(d, p, s)
        _ => false
      }
    Real | Double(_) => x is Float(_)
    Char(_) | Varchar(_) | String | Symbol => x is String(_)
    Blob => x is Blob(_)
    Clob => x is Clob(_)
    Date => x is Date(_)
    Time(_, with_tz~) =>
      match x {
        Time(time) => (time.offset is Some(_)) == with_tz
        _ => false
      }
    Timestamp(_, with_tz~) =>
      match x {
        Timestamp(ts) => (ts.time.offset is Some(_)) == with_tz
        _ => false
      }
    Interval({ start, .. }) =>
      match (x, start) {
        (IntervalYM(_), Year | Month) => true
        (IntervalDT(_), Day | Hour | Minute | Second) => true
        _ => false
      }
    Struct | Tuple => x is Tuple(_)
    List | Array(_) => x is List(_)
    Bag => x is Bag(_)
    // A sexp is a list (spec M4a section 5), so no value is a SEXP.
    Sexp => false
    Map(k, v) =>
      match x {
        Map(m) =>
          map_type_of(k) is Some(kt) &&
          map_type_of(v) is Some(vt) &&
          m.key_type == kt &&
          m.value_type == vt
        _ => false
      }
    Custom(_) => raise TypeFailure("an unknown type")
  }
  Bool(holds)
}
