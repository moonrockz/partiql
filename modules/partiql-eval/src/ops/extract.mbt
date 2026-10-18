// EXTRACT (SQL-92 6.6; spec M4d3 §4.2).

///|
/// The SQL name of a datetime field.
fn field_name(f : @ast.DatetimeField) -> String {
  match f {
    Year => "YEAR"
    Month => "MONTH"
    Day => "DAY"
    Hour => "HOUR"
    Minute => "MINUTE"
    Second => "SECOND"
    TimezoneHour => "TIMEZONE_HOUR"
    TimezoneMinute => "TIMEZONE_MINUTE"
  }
}

///|
/// Seconds and nanoseconds (magnitudes) as a decimal of `scale` fraction
/// digits; the fraction is cut to `scale` digits.
fn second_decimal(
  negative : Bool,
  seconds : Int64,
  nanos : Int32,
  scale : Int32,
) -> @ion_core.Decimal {
  let units = big64(seconds) * pow10(scale) +
    big64(nanos.to_int64()) / pow10(9 - scale)
  @ion_core.Decimal::Decimal(if negative { -units } else { units }, -scale)
}

///|
fn no_field(f : @ast.DatetimeField, x : @value.Value) -> OpFailure {
  TypeFailure("EXTRACT \{field_name(f)} from \{kind_name(x)}")
}

///|
/// A field of a time of day: the local value, the second with the value's
/// precision as scale, the offset's hours or minutes with its sign.
fn time_field(
  f : @ast.DatetimeField,
  t : @value.Time,
  x : @value.Value,
) -> @value.Value raise OpFailure {
  match f {
    Hour => Int(t.hour.to_int64())
    Minute => Int(t.minute.to_int64())
    Second =>
      Decimal(
        second_decimal(false, t.second.to_int64(), t.nanos, t.precision.min(9)),
      )
    TimezoneHour | TimezoneMinute =>
      match t.offset {
        Some(o) =>
          Int((if f is TimezoneHour { o / 60 } else { o % 60 }).to_int64())
        None => raise no_field(f, x)
      }
    _ => raise no_field(f, x)
  }
}

///|
fn extract_field(
  f : @ast.DatetimeField,
  x : @value.Value,
) -> @value.Value raise OpFailure {
  match x {
    Date(d) =>
      match f {
        Year => Int(d.year.to_int64())
        Month => Int(d.month.to_int64())
        Day => Int(d.day.to_int64())
        _ => raise no_field(f, x)
      }
    Time(t) => time_field(f, t, x)
    Timestamp(ts) =>
      match f {
        Year => Int(ts.date.year.to_int64())
        Month => Int(ts.date.month.to_int64())
        Day => Int(ts.date.day.to_int64())
        _ => time_field(f, ts.time, x)
      }
    // The value keeps no qualifier, so the fields are the normalized ones
    // (spec M4d3 §4.2, Q6).
    IntervalYM(i) => {
      let sign = if i.is_negative() { -1L } else { 1L }
      match f {
        Year => Int(sign * i.years())
        Month => Int(sign * i.months_part())
        _ => raise no_field(f, x)
      }
    }
    IntervalDT(i) => {
      let negative = i.is_negative()
      let sign = if negative { -1L } else { 1L }
      match f {
        Day => Int(sign * i.days())
        Hour => Int(sign * i.hours())
        Minute => Int(sign * i.minutes())
        Second => {
          let nanos = i.nanos_part().to_int()
          let digits = if nanos == 0 { 0 } else { needed_precision(nanos) }
          Decimal(
            second_decimal(negative, i.seconds_part(), nanos, digits.max(6)),
          )
        }
        _ => raise no_field(f, x)
      }
    }
    _ => raise no_field(f, x)
  }
}

///|
/// `EXTRACT(f FROM x)`.
pub fn extract(
  field : @ast.DatetimeField,
  args : Array[@value.Value],
) -> @value.Value raise OpFailure {
  apply("EXTRACT", [Temporal], args, xs => extract_field(field, xs[0]))
}
