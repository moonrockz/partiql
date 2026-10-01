///|
test "civil day round trip at known points" {
  @expect.expect_all(soft => {
    soft.expect(days_from_civil(1970, 1, 1)).to_equal(0L)
    soft.expect(days_from_civil(2000, 3, 1)).to_equal(11017L)
    soft.expect(days_from_civil(1969, 12, 31)).to_equal(-1L)
    soft.expect(civil_from_days(11017L)).to_equal((2000, 3, 1))
    soft.expect(civil_from_days(-1L)).to_equal((1969, 12, 31))
  })
}

///|
test "civil days and days are inverse (property)" {
  @quickcheck.check(
    (n : Int) => {
      let days = (n % 3000000).to_int64() // about ±8,000 years
      let (y, m, d) = civil_from_days(days)
      days_from_civil(y, m, d) == days
    },
    count=500,
  )
}

///|
test "timestamps with different offsets have the same instant" {
  let date = Date::new(year=2024, month=1, day=1)
  let a = Timestamp::new(
    date,
    Time::new(hour=0, minute=30, second=0, offset=Some(60)),
  )
  let b = Timestamp::new(
    Date::new(year=2023, month=12, day=31),
    Time::new(hour=23, minute=30, second=0, offset=Some(0)),
  )
  @expect.expect(a.utc_key()).to_equal(b.utc_key())
}

///|
test "time with zone keys wrap at midnight" {
  let t = Time::new(hour=0, minute=30, second=0, offset=Some(60))
  @expect.expect(t.utc_key()).to_equal((84600L, 0))
}

///|
/// The inverse of `days_from_civil` (test support).
fn civil_from_days(days : Int64) -> (Int, Int, Int) {
  let z = days + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let d = doy - (153L * mp + 2L) / 5L + 1L
  let m = if mp < 10L { mp + 3L } else { mp - 9L }
  ((if m <= 2L { y + 1L } else { y }).to_int(), m.to_int(), d.to_int())
}
