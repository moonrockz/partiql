// DATE_ADD and DATE_DIFF (spec M4d3 §4.3, §4.4).

///|
/// Whether a datetime has the field (SQL-92 6.14 SR 3): DATE has YEAR,
/// MONTH and DAY; TIME has HOUR, MINUTE and SECOND; TIMESTAMP has all six.
fn has_field(f : @ast.DatetimeField, x : @value.Value) -> Bool {
  match (f, x) {
    (Year | Month | Day, Date(_) | Timestamp(_)) => true
    (Hour | Minute | Second, Time(_) | Timestamp(_)) => true
    _ => false
  }
}

///|
/// `x` plus `n` units of `f`. The result keeps the type, precision and
/// offset of `x`.
fn add_units(
  f : @ast.DatetimeField,
  n : @value.Value,
  x : @value.Value,
) -> @value.Value raise OpFailure {
  let count = match n {
    Int(i) => big64(i)
    BigInt(b) => b
    _ => raise TypeFailure("the quantity of DATE_ADD must be an integer")
  }
  if !has_field(f, x) {
    raise TypeFailure("DATE_ADD \{field_name(f)} to \{kind_name(x)}")
  }
  match f {
    Year | Month => {
      let months = if f is Year { count * 12N } else { count }
      if !fits_int64(months) {
        raise DataFailure("datetime field overflow in DATE_ADD")
      }
      match x {
        Date(d) => Date(date_add_months(d, months.to_int64()))
        Timestamp(ts) =>
          Timestamp(
            @value.Timestamp::new(
              date_add_months(ts.date, months.to_int64()),
              ts.time,
            ),
          )
        _ => raise TypeFailure("DATE_ADD \{field_name(f)} to \{kind_name(x)}")
      }
    }
    _ => {
      let nanos = count * field_nanos(f)
      match x {
        Date(d) => Date(date_shift(d, nanos))
        Timestamp(ts) => Timestamp(timestamp_shift(ts, nanos))
        Time(t) => Time(time_shift(t, nanos))
        _ => raise TypeFailure("DATE_ADD \{field_name(f)} to \{kind_name(x)}")
      }
    }
  }
}

///|
/// `DATE_ADD(f, n, x)`.
pub fn date_add(
  field : @ast.DatetimeField,
  args : Array[@value.Value],
) -> @value.Value raise OpFailure {
  apply("DATE_ADD", [Integer, Datetime], args, xs => {
    add_units(field, xs[0], xs[1])
  })
}

///|
/// The instant of a datetime in nanoseconds; a DATE is midnight, and a value
/// without an offset is in the session zone (SQL-92 4.5.3).
fn zoned_instant(
  v : @value.Value,
  zone : ZoneOffset,
) -> @bigint.BigInt raise OpFailure {
  guard instant(v) is Some(n) else {
    raise TypeFailure("\{kind_name(v)} is not a datetime")
  }
  let no_offset = match v {
    Date(_) => true
    Timestamp(ts) => ts.time.offset is None
    Time(t) => t.offset is None
    _ => false
  }
  if no_offset {
    n - minutes_nanos(zone.minutes)
  } else {
    n
  }
}

///|
fn as_timestamp(v : @value.Value) -> @value.Timestamp raise OpFailure {
  match v {
    Timestamp(ts) => ts
    Date(d) =>
      @value.Timestamp::new(
        d,
        @value.Time::new(hour=0, minute=0, second=0, precision=0) catch {
          _ => raise DataFailure("a time out of range")
        },
      )
    _ => raise TypeFailure("\{kind_name(v)} is not a date or timestamp")
  }
}

///|
/// The local calendar position of a timestamp seen at `offset` minutes: the
/// year and month, and the nanoseconds into the month (day and time of
/// day). No range check: DATE_DIFF gives an integer, not a datetime, so a
/// value from data outside 0001-9999 still compares.
fn month_position(
  ts : @value.Timestamp,
  shift : Int32,
) -> (Int64, Int64, @bigint.BigInt) {
  let total = big64(date_days(ts.date)) * nanos_per_day +
    day_nanos(ts.time) +
    minutes_nanos(shift)
  let (days, rest) = floor_split(total, nanos_per_day)
  let (year, month, day) = civil_from_days(days.to_int64())
  (
    year.to_int64(),
    month.to_int64(),
    big64(day.to_int64()) * nanos_per_day + rest,
  )
}

///|
/// Complete calendar months from `a` to `b`, as Java `ChronoUnit.MONTHS`:
/// `b` moves to `a`'s offset, then a month counts only when `b`'s day and
/// time of day reach `a`'s.
fn month_difference(
  a : @value.Timestamp,
  b : @value.Timestamp,
  zone : ZoneOffset,
) -> Int64 {
  let offset_a = a.time.offset.unwrap_or(zone.minutes)
  let offset_b = b.time.offset.unwrap_or(zone.minutes)
  let (year_a, month_a, rest_a) = month_position(a, 0)
  let (year_b, month_b, rest_b) = month_position(b, offset_a - offset_b)
  let m = year_b * 12L + month_b - (year_a * 12L + month_a)
  if m > 0L && rest_b.compare(rest_a) < 0 {
    m - 1L
  } else if m < 0L && rest_b.compare(rest_a) > 0 {
    m + 1L
  } else {
    m
  }
}

///|
/// `b - a` in whole units of `f`, toward zero (spec M4d3 §4.4).
fn diff_units(
  f : @ast.DatetimeField,
  a : @value.Value,
  b : @value.Value,
  zone : ZoneOffset,
) -> @value.Value raise OpFailure {
  let both_times = a is Time(_) && b is Time(_)
  if !both_times && !(is_point_in_time(a) && is_point_in_time(b)) {
    raise TypeFailure("DATE_DIFF of \{kind_name(a)} and \{kind_name(b)}")
  }
  if both_times && f is (Year | Month | Day) {
    raise TypeFailure("DATE_DIFF \{field_name(f)} of TIME values")
  }
  match f {
    Year | Month => {
      let m = month_difference(as_timestamp(a), as_timestamp(b), zone)
      Int(if f is Year { m / 12L } else { m })
    }
    _ => {
      let delta = zoned_instant(b, zone) - zoned_instant(a, zone)
      Int((delta / field_nanos(f)).to_int64())
    }
  }
}

///|
/// `DATE_DIFF(f, a, b)`.
pub fn date_diff(
  field : @ast.DatetimeField,
  args : Array[@value.Value],
  zone~ : ZoneOffset,
) -> @value.Value raise OpFailure {
  apply("DATE_DIFF", [Datetime, Datetime], args, xs => {
    diff_units(field, xs[0], xs[1], zone)
  })
}
