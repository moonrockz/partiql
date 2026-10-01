///|
/// A year-month interval, as a signed number of months.
pub struct IntervalYM {
  months : Int64
} derive(Debug)

///|
pub fn IntervalYM::new(months : Int64) -> IntervalYM {
  { months, }
}

///|
pub fn IntervalYM::from_parts(
  negative~ : Bool,
  years~ : Int64,
  months~ : Int64,
) -> IntervalYM {
  let total = years * 12L + months
  { months: if negative { -total } else { total }, }
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
pub fn IntervalDT::new(seconds : Int64, nanos : Int64) -> IntervalDT {
  let carry = nanos / 1000000000L
  let rest = nanos % 1000000000L
  let (s, n) = if rest < 0L {
    (seconds + carry - 1L, rest + 1000000000L)
  } else {
    (seconds + carry, rest)
  }
  { seconds: s, nanos: n.to_int(), }
}

///|
pub fn IntervalDT::from_parts(
  negative~ : Bool,
  days~ : Int64,
  hours~ : Int64,
  minutes~ : Int64,
  seconds~ : Int64,
  nanos~ : Int64,
) -> IntervalDT {
  let total = days * 86400L + hours * 3600L + minutes * 60L + seconds
  if negative {
    IntervalDT::new(-total, -nanos)
  } else {
    IntervalDT::new(total, nanos)
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
