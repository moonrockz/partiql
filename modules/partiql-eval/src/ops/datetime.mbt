// Datetime and interval arithmetic and ordering (spec M4a section 4).

///|
let nanos_per_second : @bigint.BigInt = 1000000000N

///|
let nanos_per_day : @bigint.BigInt = 86400000000000N

///|
fn big64(n : Int64) -> @bigint.BigInt {
  @bigint.BigInt::from_int64(n)
}

///|
fn fits_int64(n : @bigint.BigInt) -> Bool {
  n.compare_int64(9223372036854775807L) <= 0 &&
  n.compare_int64(-9223372036854775808L) > 0
}

///|
/// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
fn days_from_civil(year : Int, month : Int, day : Int) -> Int64 {
  let y = (if month <= 2 { year - 1 } else { year }).to_int64()
  let era = (if y >= 0L { y } else { y - 399L }) / 400L
  let yoe = y - era * 400L
  let m = month.to_int64()
  let doy = (153L * (if m > 2L { m - 3L } else { m + 9L }) + 2L) / 5L +
    day.to_int64() -
    1L
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy
  era * 146097L + doe - 719468L
}

///|
/// The year, month and day of a day number (Hinnant's civil_from_days). The
/// day number is within ±4e11, so that the year fits in an Int.
fn civil_from_days(days : Int64) -> (Int, Int, Int) {
  let z = days + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let d = doy - (153L * mp + 2L) / 5L + 1L
  let m = if mp < 10L { mp + 3L } else { mp - 9L }
  let y = yoe + era * 400L + (if m <= 2L { 1L } else { 0L })
  (y.to_int(), m.to_int(), d.to_int())
}

///|
fn leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
fn month_length(year : Int, month : Int) -> Int {
  match month {
    2 => if leap_year(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
/// Days beyond which a date is out of range anyway; it keeps the arithmetic
/// inside Int64.
let max_day_number : Int64 = 400000000000L

///|
fn date_of_days(days : Int64) -> @value.Date raise OpFailure {
  if days.abs() > max_day_number {
    raise DataFailure("a date out of range")
  }
  let (year, month, day) = civil_from_days(days)
  @value.Date::new(year~, month~, day~) catch {
    _ => raise DataFailure("a date out of range")
  }
}

///|
fn date_days(d : @value.Date) -> Int64 {
  days_from_civil(d.year, d.month, d.day)
}

///|
/// The date `months` later; the day is cut back to the end of a shorter month.
fn date_add_months(
  d : @value.Date,
  months : Int64,
) -> @value.Date raise OpFailure {
  if months.abs() > 100000000000L {
    raise DataFailure("a date out of range")
  }
  let total = d.year.to_int64() * 12L + (d.month - 1).to_int64() + months
  let mut years = total / 12L
  let mut rest = total % 12L
  if rest < 0L {
    years = years - 1L
    rest = rest + 12L
  }
  if years.abs() > 2000000000L {
    raise DataFailure("a date out of range")
  }
  let year = years.to_int()
  let month = rest.to_int() + 1
  @value.Date::new(year~, month~, day=d.day.min(month_length(year, month))) catch {
    _ => raise DataFailure("a date out of range")
  }
}

///|
/// The nanoseconds of a day-time interval.
fn dt_nanos(i : @value.IntervalDT) -> @bigint.BigInt {
  big64(i.seconds) * nanos_per_second + big64(i.nanos.to_int64())
}

///|
fn dt_value(n : @bigint.BigInt) -> @value.Value raise OpFailure {
  let seconds = n / nanos_per_second
  if !fits_int64(seconds) {
    raise DataFailure("an interval out of range")
  }
  let rest = (n % nanos_per_second).to_int64()
  IntervalDT(
    @value.IntervalDT::new(seconds.to_int64(), rest) catch {
      _ => raise DataFailure("an interval out of range")
    },
  )
}

///|
fn ym_value(months : @bigint.BigInt) -> @value.Value raise OpFailure {
  if !fits_int64(months) {
    raise DataFailure("an interval out of range")
  }
  IntervalYM(
    @value.IntervalYM::new(months.to_int64()) catch {
      _ => raise DataFailure("an interval out of range")
    },
  )
}

///|
/// The fewest fraction digits that show `nanos`.
fn needed_precision(nanos : Int) -> Int {
  let mut p = 9
  let mut rest = nanos
  while p > 0 && rest % 10 == 0 {
    rest = rest / 10
    p = p - 1
  }
  p
}

///|
/// The time of day at `rest` nanoseconds into the day.
fn time_at(
  rest : @bigint.BigInt,
  precision : Int,
  offset : Int?,
) -> @value.Time raise OpFailure {
  let seconds = (rest / nanos_per_second).to_int()
  let nanos = (rest % nanos_per_second).to_int()
  @value.Time::new(
    hour=seconds / 3600,
    minute=seconds % 3600 / 60,
    second=seconds % 60,
    nanos~,
    precision=precision.max(needed_precision(nanos)),
    offset~,
  ) catch {
    _ => raise DataFailure("a time out of range")
  }
}

///|
fn day_nanos(t : @value.Time) -> @bigint.BigInt {
  big64((t.hour * 3600 + t.minute * 60 + t.second).to_int64()) *
  nanos_per_second +
  big64(t.nanos.to_int64())
}

///|
fn floor_split(
  n : @bigint.BigInt,
  unit : @bigint.BigInt,
) -> (@bigint.BigInt, @bigint.BigInt) {
  let q = n / unit
  let r = n % unit
  if r.compare_int(0) < 0 {
    (q - 1N, r + unit)
  } else {
    (q, r)
  }
}

///|
fn time_shift(
  t : @value.Time,
  n : @bigint.BigInt,
) -> @value.Time raise OpFailure {
  let (_, rest) = floor_split(day_nanos(t) + n, nanos_per_day)
  time_at(rest, t.precision, t.offset)
}

///|
fn timestamp_shift(
  ts : @value.Timestamp,
  n : @bigint.BigInt,
) -> @value.Timestamp raise OpFailure {
  let shifted = big64(date_days(ts.date)) * nanos_per_day +
    day_nanos(ts.time) +
    n
  let (days, rest) = floor_split(shifted, nanos_per_day)
  if !fits_int64(days) {
    raise DataFailure("a timestamp out of range")
  }
  @value.Timestamp::new(
    date_of_days(days.to_int64()),
    time_at(rest, ts.time.precision, ts.time.offset),
  )
}

///|
/// A date plus a day-time interval of whole days.
fn date_shift(
  d : @value.Date,
  n : @bigint.BigInt,
) -> @value.Date raise OpFailure {
  let (days, rest) = floor_split(n, nanos_per_day)
  if !rest.is_zero() {
    raise TypeFailure("a date plus an interval with a part under a day")
  }
  if !fits_int64(days) {
    raise DataFailure("a date out of range")
  }
  date_of_days(date_days(d) + days.to_int64())
}

///|
/// The instant of a date, a timestamp or a time of day, in nanoseconds; a
/// date is midnight and a value without an offset is at offset 0.
fn instant(v : @value.Value) -> @bigint.BigInt? {
  match v {
    Date(d) => Some(big64(date_days(d)) * nanos_per_day)
    Timestamp(ts) =>
      Some(
        big64(date_days(ts.date)) * nanos_per_day +
        day_nanos(ts.time) -
        big64((ts.time.offset.unwrap_or(0) * 60).to_int64()) * nanos_per_second,
      )
    Time(t) =>
      Some(
        day_nanos(t) -
        big64((t.offset.unwrap_or(0) * 60).to_int64()) * nanos_per_second,
      )
    _ => None
  }
}

///|
fn is_point_in_time(v : @value.Value) -> Bool {
  v is (Date(_) | Timestamp(_))
}

///|
/// The order of two datetimes of one kind (a date counts as a timestamp) or
/// two intervals of one kind; `None` for any other pair.
fn datetime_order(x : @value.Value, y : @value.Value) -> Int? {
  match (x, y) {
    (IntervalYM(p), IntervalYM(q)) => Some(p.months.compare(q.months))
    (IntervalDT(p), IntervalDT(q)) => Some(dt_nanos(p).compare(dt_nanos(q)))
    (Time(_), Time(_)) =>
      match (instant(x), instant(y)) {
        (Some(p), Some(q)) => Some(p.compare(q))
        _ => None
      }
    _ =>
      if is_point_in_time(x) && is_point_in_time(y) {
        match (instant(x), instant(y)) {
          (Some(p), Some(q)) => Some(p.compare(q))
          _ => None
        }
      } else {
        None
      }
  }
}

///|
/// A float as the decimal of its exact binary value, not of its shortest text.
fn exact_decimal(f : Double) -> @ion_core.Decimal raise OpFailure {
  if f.is_nan() || f.is_inf() {
    raise DataFailure("NaN or infinity in interval arithmetic")
  }
  let bits = f.reinterpret_as_int64()
  let negative = bits < 0L
  let exponent_bits = ((bits >> 52) & 0x7FFL).to_int()
  let fraction = bits & 0xFFFFFFFFFFFFFL
  let mut mantissa = if exponent_bits == 0 {
    fraction
  } else {
    fraction | (1L << 52)
  }
  let mut exponent = if exponent_bits == 0 {
    -1074
  } else {
    exponent_bits - 1075
  }
  if mantissa == 0L {
    return @ion_core.Decimal::new(0N, 0)
  }
  while mantissa % 2L == 0L {
    mantissa = mantissa / 2L
    exponent += 1
  }
  let m = if negative { -big64(mantissa) } else { big64(mantissa) }
  if exponent >= 0 {
    @ion_core.Decimal::new(
      m * @bigint.BigInt::from_int(2).pow(@bigint.BigInt::from_int(exponent)),
      0,
    )
  } else {
    @ion_core.Decimal::new(
      m * @bigint.BigInt::from_int(5).pow(@bigint.BigInt::from_int(-exponent)),
      exponent,
    )
  }
}

///|
/// The integer part of a decimal, toward zero.
fn truncated(d : @ion_core.Decimal) -> @bigint.BigInt raise OpFailure {
  let e = d.exponent()
  if e >= 0 {
    if e > 60 {
      raise DataFailure("an interval out of range")
    }
    d.coefficient() * pow10(e)
  } else if -e > digit_count(d.coefficient()) {
    0N
  } else {
    d.coefficient() / pow10(-e)
  }
}

///|
/// The value of a number as the factor of an interval. A float is taken at
/// its exact binary value.
fn factor(n : Num) -> @ion_core.Decimal raise OpFailure {
  match n {
    Whole(w) => @ion_core.Decimal::new(w, 0)
    Exact(d) => d
    Approx(f) => exact_decimal(f)
  }
}

///|
fn scaled_ym(months : @bigint.BigInt) -> @value.Value raise OpFailure {
  ym_value(months)
}

///|
fn scaled_dt(nanos : @bigint.BigInt) -> @value.Value raise OpFailure {
  dt_value(nanos)
}

///|
/// Cuts a count of nanoseconds back to whole microseconds, the fraction
/// precision of an interval.
fn to_micros(nanos : @bigint.BigInt) -> @bigint.BigInt {
  nanos - nanos % 1000N
}

///|
/// An interval times a number. A year-month interval counts months, a
/// day-time one nanoseconds; a fractional factor cuts the result back to
/// microseconds.
fn scale_by(interval : @value.Value, n : Num) -> @value.Value raise OpFailure {
  let exact = n is Whole(_)
  match interval {
    IntervalYM(i) => {
      let product = decimal_mul(
        @ion_core.Decimal::new(big64(i.months), 0),
        factor(n),
      )
      scaled_ym(truncated(product))
    }
    IntervalDT(i) => {
      let product = decimal_mul(
        @ion_core.Decimal::new(dt_nanos(i), 0),
        factor(n),
      )
      let nanos = truncated(product)
      scaled_dt(if exact { nanos } else { to_micros(nanos) })
    }
    _ => raise TypeFailure("a scale of a value that is not an interval")
  }
}

///|
/// An interval divided by a number; a zero divisor is a `DataFailure`.
fn divide_by(interval : @value.Value, n : Num) -> @value.Value raise OpFailure {
  match interval {
    IntervalYM(i) => {
      let divisor = factor(n)
      let quotient = decimal_div(
        @ion_core.Decimal::new(big64(i.months), 0),
        divisor,
      )
      scaled_ym(truncated(quotient))
    }
    IntervalDT(i) => {
      let divisor = factor(n)
      let quotient = decimal_div(
        @ion_core.Decimal::new(dt_nanos(i), 0),
        divisor,
      )
      scaled_dt(to_micros(truncated(quotient)))
    }
    _ => raise TypeFailure("a division of a value that is not an interval")
  }
}

///|
fn is_interval(v : @value.Value) -> Bool {
  v is (IntervalYM(_) | IntervalDT(_))
}

///|
fn is_datetime(v : @value.Value) -> Bool {
  v is (Date(_) | Time(_) | Timestamp(_))
}

///|
/// `datetime + interval` (or `datetime - interval` for a negative `sign`).
fn shift_datetime(
  point : @value.Value,
  interval : @value.Value,
  negative~ : Bool,
) -> @value.Value raise OpFailure {
  match (point, interval) {
    (Date(d), IntervalYM(i)) =>
      Date(date_add_months(d, if negative { -i.months } else { i.months }))
    (Timestamp(ts), IntervalYM(i)) =>
      Timestamp(
        @value.Timestamp::new(
          date_add_months(ts.date, if negative { -i.months } else { i.months }),
          ts.time,
        ),
      )
    (Date(d), IntervalDT(i)) =>
      Date(date_shift(d, if negative { -dt_nanos(i) } else { dt_nanos(i) }))
    (Timestamp(ts), IntervalDT(i)) =>
      Timestamp(
        timestamp_shift(ts, if negative { -dt_nanos(i) } else { dt_nanos(i) }),
      )
    (Time(t), IntervalDT(i)) =>
      Time(time_shift(t, if negative { -dt_nanos(i) } else { dt_nanos(i) }))
    (Time(_), IntervalYM(_)) =>
      raise TypeFailure("a time and a year-month interval")
    _ => raise TypeFailure("a datetime and an interval that do not combine")
  }
}

///|
/// `x + y` for datetimes and intervals; `None` when neither side is one, so
/// that the number rules decide.
fn datetime_add(
  x : @value.Value,
  y : @value.Value,
) -> @value.Value? raise OpFailure {
  match (x, y) {
    (IntervalYM(p), IntervalYM(q)) =>
      Some(ym_value(big64(p.months) + big64(q.months)))
    (IntervalDT(p), IntervalDT(q)) => Some(dt_value(dt_nanos(p) + dt_nanos(q)))
    _ =>
      if is_datetime(x) && is_interval(y) {
        Some(shift_datetime(x, y, negative=false))
      } else if is_interval(x) && is_datetime(y) {
        Some(shift_datetime(y, x, negative=false))
      } else {
        None
      }
  }
}

///|
/// `x - y` for datetimes and intervals.
fn datetime_sub(
  x : @value.Value,
  y : @value.Value,
) -> @value.Value? raise OpFailure {
  match (x, y) {
    (IntervalYM(p), IntervalYM(q)) =>
      Some(ym_value(big64(p.months) - big64(q.months)))
    (IntervalDT(p), IntervalDT(q)) => Some(dt_value(dt_nanos(p) - dt_nanos(q)))
    _ =>
      if is_datetime(x) && is_interval(y) {
        Some(shift_datetime(x, y, negative=true))
      } else if (is_point_in_time(x) && is_point_in_time(y)) ||
        (x is Time(_) && y is Time(_)) {
        match (instant(x), instant(y)) {
          (Some(p), Some(q)) => Some(dt_value(p - q))
          _ => None
        }
      } else {
        None
      }
  }
}

///|
/// `x * y` for an interval and a number in either order.
fn datetime_mul(
  x : @value.Value,
  y : @value.Value,
) -> @value.Value? raise OpFailure {
  if is_interval(x) {
    match number(y) {
      Some(n) => Some(scale_by(x, n))
      None => None
    }
  } else if is_interval(y) {
    match number(x) {
      Some(n) => Some(scale_by(y, n))
      None => None
    }
  } else {
    None
  }
}

///|
/// `x / y` for an interval and a number.
fn datetime_div(
  x : @value.Value,
  y : @value.Value,
) -> @value.Value? raise OpFailure {
  if is_interval(x) {
    match number(y) {
      Some(n) => Some(divide_by(x, n))
      None => None
    }
  } else {
    None
  }
}

///|
/// `-x` for an interval.
fn interval_neg(v : @value.Value) -> @value.Value? raise OpFailure {
  match v {
    IntervalYM(i) => Some(ym_value(-big64(i.months)))
    IntervalDT(i) => Some(dt_value(-dt_nanos(i)))
    _ => None
  }
}

///|
/// `x = y` for two datetimes of the kinds that `datetime_order` compares.
fn datetime_equal(x : @value.Value, y : @value.Value) -> @value.Value? {
  match datetime_order(x, y) {
    Some(c) => Some(Bool(c == 0))
    None => None
  }
}

///|
/// The time `nanos` later, around the day.
pub fn shift_time(
  t : @value.Time,
  nanos : Int64,
) -> @value.Time raise OpFailure {
  time_shift(t, big64(nanos))
}

///|
/// The timestamp `nanos` later.
pub fn shift_timestamp(
  ts : @value.Timestamp,
  nanos : Int64,
) -> @value.Timestamp raise OpFailure {
  timestamp_shift(ts, big64(nanos))
}
