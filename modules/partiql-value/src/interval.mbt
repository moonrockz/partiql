///|
/// An interval that does not fit the representation.
pub(all) suberror IntervalError {
  Overflow(String)
} derive(Debug, Eq)

///|
let int64_min_big : @bigint.BigInt = @bigint.BigInt::from_int64(
  -9223372036854775808L,
)

///|
let int64_max_big : @bigint.BigInt = @bigint.BigInt::from_int64(
  9223372036854775807L,
)

///|
/// Int64 min is excluded, so that every value has a magnitude.
fn fit_int64(n : @bigint.BigInt, what : String) -> Int64 raise IntervalError {
  if n.compare(int64_min_big) <= 0 || n.compare(int64_max_big) > 0 {
    raise Overflow("\{what} does not fit in Int64")
  }
  n.to_int64()
}

///|
fn big(n : Int64) -> @bigint.BigInt {
  @bigint.BigInt::from_int64(n)
}

///|
/// A year-month interval, as a signed number of months.
pub struct IntervalYM {
  months : Int64
} derive(Debug)

///|
pub fn IntervalYM::new(months : Int64) -> IntervalYM raise IntervalError {
  { months: fit_int64(big(months), "months"), }
}

///|
pub fn IntervalYM::from_parts(
  negative~ : Bool,
  years~ : Int64,
  months~ : Int64,
) -> IntervalYM raise IntervalError {
  let total = big(years) * 12N + big(months)
  { months: fit_int64(if negative { -total } else { total }, "months"), }
}

///|
pub fn IntervalYM::is_negative(self : IntervalYM) -> Bool {
  self.months < 0L
}

///|
fn IntervalYM::magnitude(self : IntervalYM) -> Int64 {
  if self.months < 0L {
    -self.months
  } else {
    self.months
  }
}

///|
pub fn IntervalYM::years(self : IntervalYM) -> Int64 {
  self.magnitude() / 12L
}

///|
pub fn IntervalYM::months_part(self : IntervalYM) -> Int64 {
  self.magnitude() % 12L
}

///|
/// A day-time interval: `seconds` + `nanos` / 10^9, with `nanos` in
/// 0..999,999,999 (floor form).
pub struct IntervalDT {
  seconds : Int64
  nanos : Int
} derive(Debug)

///|
/// Floor form of seconds + nanos / 10^9, computed in BigInt arithmetic.
fn normalize_dt(
  seconds : @bigint.BigInt,
  nanos : @bigint.BigInt,
) -> IntervalDT raise IntervalError {
  let billion = 1000000000N
  let total = seconds * billion + nanos
  let mut s = total / billion
  let mut n = total % billion
  if n.compare(0N) < 0 {
    s = s - 1N
    n = n + billion
  }
  { seconds: fit_int64(s, "seconds"), nanos: n.to_int(), }
}

///|
pub fn IntervalDT::new(
  seconds : Int64,
  nanos : Int64,
) -> IntervalDT raise IntervalError {
  normalize_dt(big(seconds), big(nanos))
}

///|
pub fn IntervalDT::from_parts(
  negative~ : Bool,
  days~ : Int64,
  hours~ : Int64,
  minutes~ : Int64,
  seconds~ : Int64,
  nanos~ : Int64,
) -> IntervalDT raise IntervalError {
  let total = big(days) * 86400N +
    big(hours) * 3600N +
    big(minutes) * 60N +
    big(seconds)
  if negative {
    normalize_dt(-total, -big(nanos))
  } else {
    normalize_dt(total, big(nanos))
  }
}

///|
pub fn IntervalDT::is_negative(self : IntervalDT) -> Bool {
  self.seconds < 0L
}

///|
/// The magnitude as (seconds, nanos) with nanos in 0..999,999,999.
fn IntervalDT::magnitude(self : IntervalDT) -> (Int64, Int64) {
  if self.seconds >= 0L {
    (self.seconds, self.nanos.to_int64())
  } else if self.nanos == 0 {
    (-self.seconds, 0L)
  } else {
    (-self.seconds - 1L, 1000000000L - self.nanos.to_int64())
  }
}

///|
pub fn IntervalDT::days(self : IntervalDT) -> Int64 {
  self.magnitude().0 / 86400L
}

///|
pub fn IntervalDT::hours(self : IntervalDT) -> Int64 {
  self.magnitude().0 % 86400L / 3600L
}

///|
pub fn IntervalDT::minutes(self : IntervalDT) -> Int64 {
  self.magnitude().0 % 3600L / 60L
}

///|
pub fn IntervalDT::seconds_part(self : IntervalDT) -> Int64 {
  self.magnitude().0 % 60L
}

///|
pub fn IntervalDT::nanos_part(self : IntervalDT) -> Int64 {
  self.magnitude().1
}
