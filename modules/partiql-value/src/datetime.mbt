///|
/// A date, time or timestamp field that is out of range.
pub(all) suberror DateTimeError {
  InvalidDate(String)
  InvalidTime(String)
} derive(Debug, Eq)

///|
/// A calendar date (proleptic Gregorian).
pub struct Date {
  year : Int
  month : Int
  day : Int
} derive(Debug)

///|
fn is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    2 => if is_leap_year(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
pub fn Date::new(
  year~ : Int,
  month~ : Int,
  day~ : Int,
) -> Date raise DateTimeError {
  if year < 1 || year > 9999 {
    raise InvalidDate("year \{year} is not in 1..9999")
  }
  if month < 1 || month > 12 {
    raise InvalidDate("month \{month} is not in 1..12")
  }
  if day < 1 || day > days_in_month(year, month) {
    raise InvalidDate("day \{day} is not valid for \{year}-\{month}")
  }
  { year, month, day, }
}

///|
/// A time of day. `offset` is minutes east of UTC; `None` means WITHOUT TIME
/// ZONE. `precision` is the number of fractional-second digits (TIME(p)).
pub struct Time {
  hour : Int
  minute : Int
  second : Int
  nanos : Int
  precision : Int
  offset : Int?
} derive(Debug)

///|
fn pow10(n : Int) -> Int {
  let mut result = 1
  for _ in 0..<n {
    result *= 10
  }
  result
}

///|
pub fn Time::new(
  hour~ : Int,
  minute~ : Int,
  second~ : Int,
  nanos? : Int = 0,
  precision? : Int = 0,
  offset? : Int? = None,
) -> Time raise DateTimeError {
  if hour < 0 || hour > 23 {
    raise InvalidTime("hour \{hour} is not in 0..23")
  }
  if minute < 0 || minute > 59 {
    raise InvalidTime("minute \{minute} is not in 0..59")
  }
  if second < 0 || second > 59 {
    raise InvalidTime("second \{second} is not in 0..59")
  }
  if precision < 0 || precision > 9 {
    raise InvalidTime("precision \{precision} is not in 0..9")
  }
  if nanos < 0 || nanos > 999999999 {
    raise InvalidTime("nanos \{nanos} is not in 0..999999999")
  }
  if nanos % pow10(9 - precision) != 0 {
    raise InvalidTime("nanos \{nanos} needs more than \{precision} digits")
  }
  if offset is Some(minutes) && (minutes < -1439 || minutes > 1439) {
    raise InvalidTime("offset \{minutes} is not in -1439..1439")
  }
  { hour, minute, second, nanos, precision, offset, }
}

///|
/// A date and a time. The time's offset is the timestamp's offset.
pub struct Timestamp {
  date : Date
  time : Time
} derive(Debug)

///|
pub fn Timestamp::new(date : Date, time : Time) -> Timestamp {
  { date, time, }
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
fn Time::seconds_of_day(self : Time) -> Int64 {
  (self.hour * 3600 + self.minute * 60 + self.second).to_int64()
}

///|
fn Time::offset_seconds(self : Time) -> Int64 {
  match self.offset {
    Some(minutes) => (minutes * 60).to_int64()
    None => 0L
  }
}

///|
/// Fields as written, ignoring the offset.
fn Time::local_key(self : Time) -> (Int64, Int) {
  (self.seconds_of_day(), self.nanos)
}

///|
/// UTC seconds of day, modulo 86,400.
fn Time::utc_key(self : Time) -> (Int64, Int) {
  let s = (self.seconds_of_day() - self.offset_seconds()) % 86400L
  (if s < 0L { s + 86400L } else { s }, self.nanos)
}

///|
fn Timestamp::local_key(self : Timestamp) -> (Int64, Int) {
  let days = days_from_civil(self.date.year, self.date.month, self.date.day)
  (days * 86400L + self.time.seconds_of_day(), self.time.nanos)
}

///|
/// Seconds since 1970-01-01T00:00:00Z and nanos.
fn Timestamp::utc_key(self : Timestamp) -> (Int64, Int) {
  let (seconds, nanos) = self.local_key()
  (seconds - self.time.offset_seconds(), nanos)
}
