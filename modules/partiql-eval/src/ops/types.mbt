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
/// Whether a fraction of a second fits TIME(p) or TIMESTAMP(p): its
/// significant digits are no more than `p`. The declared precision of a value
/// is not used: a literal without a fraction declares one digit (see
/// `time_literal`).
fn fraction_fits(nanos : Int, precision : Int?) -> Bool {
  match precision {
    None => true
    Some(p) => needed_precision(nanos) <= p
  }
}

///|
/// The nanoseconds of one unit of a day-time interval field.
fn field_nanos(f : @ast.DatetimeField) -> @bigint.BigInt {
  match f {
    Day => nanos_per_day
    Hour => 3600N * nanos_per_second
    Minute => 60N * nanos_per_second
    _ => nanos_per_second
  }
}

///|
/// Whether `n` has no more than `p` digits.
fn within_digits(n : @bigint.BigInt, p : Int) -> Bool {
  n.is_zero() || digit_count(n) <= p
}

///|
/// Whether an interval fits the qualifier: of its class (year-month or
/// day-time), a whole number of the last field's unit, and with no more
/// leading digits than the leading precision (default 2; fraction default 6).
/// Lowering has checked that the qualifier is valid.
fn interval_fits(v : @value.Value, q : @ast.IntervalQualifier) -> Bool {
  let leading = q.start_precision.unwrap_or(2)
  let last = q.end.unwrap_or(q.start)
  match (v, q.start) {
    (IntervalYM(i), Year | Month) => {
      let months = abs_int(big64(i.months))
      let whole = last is Month || (months % 12N).is_zero()
      let lead = if q.start is Year { months / 12N } else { months }
      whole && within_digits(lead, leading)
    }
    (IntervalDT(i), Day | Hour | Minute | Second) => {
      let nanos = abs_int(dt_nanos(i))
      // The smallest step: one unit of the last field, or of the last
      // fraction digit when that field is SECOND.
      let step = if last is Second {
        pow10(9 - q.fractional_precision.unwrap_or(6))
      } else {
        field_nanos(last)
      }
      (nanos % step).is_zero() &&
      within_digits(nanos / field_nanos(q.start), leading)
    }
    _ => false
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
    // CHAR(n) holds exactly n characters, VARCHAR(n) at most n (code points).
    Char(Some(n)) => x is String(s) && s.char_length() == n
    Varchar(Some(n)) => x is String(s) && s.char_length() <= n
    Char(None) | Varchar(None) | String | Symbol => x is String(_)
    Blob => x is Blob(_)
    Clob => x is Clob(_)
    Date => x is Date(_)
    Time(p, with_tz~) =>
      match x {
        Time(time) =>
          (time.offset is Some(_)) == with_tz && fraction_fits(time.nanos, p)
        _ => false
      }
    Timestamp(p, with_tz~) =>
      match x {
        Timestamp(ts) =>
          (ts.time.offset is Some(_)) == with_tz &&
          fraction_fits(ts.time.nanos, p)
        _ => false
      }
    Interval(q) => interval_fits(x, q)
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
