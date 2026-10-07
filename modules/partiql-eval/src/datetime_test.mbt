///|
fn date(year : Int, month : Int, day : Int) -> @value.Value raise Error {
  Date(@value.Date::new(year~, month~, day~))
}

///|
fn dt(seconds : Int64, nanos : Int64) -> @value.Value raise Error {
  IntervalDT(@value.IntervalDT::new(seconds, nanos))
}

///|
fn ym(months : Int64) -> @value.Value raise Error {
  IntervalYM(@value.IntervalYM::new(months))
}

///|
test "datetime and interval literals" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("DATE '2021-02-28'"))
    .to_equal(Date(@value.Date::new(year=2021, month=2, day=28)))
    soft
    .expect(ev("DATE '2021-02-28' + INTERVAL '1' DAY"))
    .to_equal(Date(@value.Date::new(year=2021, month=3, day=1)))
    soft
    .expect(ev("INTERVAL '3' YEAR + INTERVAL '2' MONTH"))
    .to_equal(IntervalYM(@value.IntervalYM::new(38L)))
    soft
    .expect(ev("INTERVAL '2' DAY * 2"))
    .to_equal(IntervalDT(@value.IntervalDT::new(4L * 86400L, 0L)))
    soft.expect(ev("TIME '12:00:00' < TIME '13:00:00'")).to_equal(Bool(true))
  })
  for mode in [@eval.Mode::Permissive, Strict] {
    @expect.expect_call(() => ev("INTERVAL '3' YEAR / 0", mode~)).to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    @expect.expect_call(() => ev("DATE '2021-02-30'", mode~)).to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
  }
}

///|
test "time and timestamp literals" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("TIME '01:01:01.111111111'"))
    .to_equal(
      Time(
        @value.Time::new(
          hour=1,
          minute=1,
          second=1,
          nanos=111111111,
          precision=9,
        ),
      ),
    )
    soft
    .expect(ev("TIME WITH TIME ZONE '14:30:15+05:30'"))
    .to_equal(
      Time(
        @value.Time::new(
          hour=14,
          minute=30,
          second=15,
          precision=1,
          offset=Some(330),
        ),
      ),
    )
    soft
    .expect(ev("TIME '23:59:59.999999999999'"))
    .to_equal(
      Time(
        @value.Time::new(
          hour=23,
          minute=59,
          second=59,
          nanos=999999999,
          precision=9,
        ),
      ),
    )
    soft
    .expect(ev("TIMESTAMP WITH TIME ZONE '2024-12-31 09:15:30-08:00'"))
    .to_equal(
      Timestamp(
        @value.Timestamp::new(
          @value.Date::new(year=2024, month=12, day=31),
          @value.Time::new(
            hour=9,
            minute=15,
            second=30,
            precision=1,
            offset=Some(-480),
          ),
        ),
      ),
    )
  })
  for
    source in [
      "TIME WITH TIME ZONE '12:00:00'", "TIMESTAMP WITH TIME ZONE '2025-01-01 12:00:00'",
      "TIME '25:00:00'", "TIME 'noon'", "TIMESTAMP '2025-01-01'", "DATE '2021-2-3'",
    ] {
    @expect.expect_call(() => ev(source)).to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError for \{source}",
    )
  }
}

///|
test "interval literals" {
  @expect.expect_all(soft => {
    soft.expect(ev("INTERVAL '10' YEAR")).to_equal(ym(120L))
    soft.expect(ev("INTERVAL '-3' YEAR")).to_equal(ym(-36L))
    soft.expect(ev("INTERVAL '+8' MONTH")).to_equal(ym(8L))
    soft.expect(ev("INTERVAL '-1-11' YEAR TO MONTH")).to_equal(ym(-23L))
    soft.expect(ev("INTERVAL '-1203' MONTH(4)")).to_equal(ym(-1203L))
    soft
    .expect(ev("INTERVAL '5 12' DAY TO HOUR"))
    .to_equal(dt(5L * 86400L + 12L * 3600L, 0L))
    soft
    .expect(ev("INTERVAL '1 2:30:45.123' DAY TO SECOND"))
    .to_equal(dt(86400L + 2L * 3600L + 30L * 60L + 45L, 123000000L))
    soft.expect(ev("INTERVAL '-0.2500' SECOND")).to_equal(dt(0L, -250000000L))
    // The default fraction precision is 6 digits.
    soft
    .expect(ev("INTERVAL '2.123456789' SECOND"))
    .to_equal(dt(2L, 123456000L))
    soft
    .expect(ev("INTERVAL '1.123456789' SECOND(2,3)"))
    .to_equal(dt(1L, 123000000L))
    soft
    .expect(ev("INTERVAL '999.123456' SECOND(3,6)"))
    .to_equal(dt(999L, 123456000L))
    soft
    .expect(ev("INTERVAL '-999:59.123456789' MINUTE(3) TO SECOND(9)"))
    .to_equal(dt(-(999L * 60L + 59L), -123456789L))
  })
  // The leading field is limited to its precision (2 digits by default), the
  // others to their range.
  for
    source in [
      "INTERVAL '100' MONTH", "INTERVAL '100-11' YEAR TO MONTH", "INTERVAL '100' DAY",
      "INTERVAL '100.123' SECOND", "INTERVAL '1 24' DAY TO HOUR", "INTERVAL '1 23:60' DAY TO MINUTE",
      "INTERVAL '100:59' HOUR TO MINUTE", "INTERVAL '1-12' YEAR TO MONTH", "INTERVAL '1.1234567899' SECOND",
      "INTERVAL 'x' DAY", "INTERVAL '1' DAY TO MONTH",
    ] {
    @expect.expect_call(() => ev(source)).to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError for \{source}",
    )
  }
}

///|
test "date and timestamp plus and minus an interval" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("DATE '2025-01-01' + INTERVAL '1-1' YEAR TO MONTH"))
    .to_equal(date(2026, 2, 1))
    soft
    .expect(ev("INTERVAL '1' MONTH + DATE '2025-01-31'"))
    .to_equal(date(2025, 2, 28))
    soft
    .expect(ev("DATE '2025-01-01' - INTERVAL '1' DAY"))
    .to_equal(date(2024, 12, 31))
    soft
    .expect(
      ev(
        "TIMESTAMP '2025-01-01 01:01:01.1' - INTERVAL '25:25:14.2' HOUR TO SECOND",
      ),
    )
    .to_equal(
      Timestamp(
        @value.Timestamp::new(
          @value.Date::new(year=2024, month=12, day=30),
          @value.Time::new(
            hour=23,
            minute=35,
            second=46,
            nanos=900000000,
            precision=1,
          ),
        ),
      ),
    )
    soft
    .expect(
      ev(
        "TIMESTAMP WITH TIME ZONE '2025-01-01 01:01:01.1+02:30' + INTERVAL '2' HOUR",
      ),
    )
    .to_equal(
      Timestamp(
        @value.Timestamp::new(
          @value.Date::new(year=2025, month=1, day=1),
          @value.Time::new(
            hour=3,
            minute=1,
            second=1,
            nanos=100000000,
            precision=1,
            offset=Some(150),
          ),
        ),
      ),
    )
  })
}

///|
test "time plus an interval wraps around the day" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("TIME '23:00:00' + INTERVAL '2' HOUR"))
    .to_equal(Time(@value.Time::new(hour=1, minute=0, second=0, precision=1)))
    soft
    .expect(ev("TIME '01:01:01.1' + INTERVAL '1' DAY"))
    .to_equal(
      Time(
        @value.Time::new(
          hour=1,
          minute=1,
          second=1,
          nanos=100000000,
          precision=1,
        ),
      ),
    )
    // Year-month intervals do not apply to a time.
    soft.expect(ev("TIME '01:01:01.1' + INTERVAL '1' YEAR")).to_equal(Missing)
    soft.expect(ev("INTERVAL '1' MONTH - TIME '01:01:01.1'")).to_equal(Missing)
  })
  @expect.expect_call(() => {
    ev("TIME '01:01:01.1' - INTERVAL '1' YEAR", mode=Strict)
  }).to_raise_matching(
    e => e is @eval.EvalError::TypeError(..),
    description="TypeError",
  )
}

///|
test "differences of datetimes are day-time intervals" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("DATE '2025-01-20' - DATE '2025-01-15'"))
    .to_equal(dt(5L * 86400L, 0L))
    soft
    .expect(ev("DATE '2025-01-15' - DATE '2025-01-20'"))
    .to_equal(dt(-5L * 86400L, 0L))
    soft
    .expect(ev("TIME '10:30:00' - TIME '14:45:30'"))
    .to_equal(dt(-(4L * 3600L + 15L * 60L + 30L), 0L))
    soft
    .expect(ev("TIME '08:15:45+02:00' - TIME '08:15:45'"))
    .to_equal(dt(-7200L, 0L))
    soft
    .expect(ev("DATE '2025-01-15' - TIMESTAMP '2025-01-14 21:00:00+00:00'"))
    .to_equal(dt(3L * 3600L, 0L))
    soft
    .expect(
      ev(
        "TIMESTAMP '2025-01-15 10:30:00+05:00' - TIMESTAMP '2025-01-15 10:30:00-03:00'",
      ),
    )
    .to_equal(dt(-8L * 3600L, 0L))
  })
}

///|
test "interval sums, scaling and sign" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("INTERVAL '1' YEAR - INTERVAL '1-1' YEAR TO MONTH"))
    .to_equal(ym(-1L))
    soft
    .expect(ev("INTERVAL '1' DAY + INTERVAL '1.1' SECOND"))
    .to_equal(dt(86400L + 1L, 100000000L))
    soft.expect(ev("-INTERVAL '3' YEAR")).to_equal(ym(-36L))
    soft.expect(ev("+INTERVAL '3' YEAR")).to_equal(ym(36L))
    soft.expect(ev("-INTERVAL '3' DAY")).to_equal(dt(-3L * 86400L, 0L))
    soft.expect(ev("INTERVAL -'3' YEAR")).to_equal(ym(-36L))
    soft.expect(ev("2 * INTERVAL '7' MONTH")).to_equal(ym(14L))
    soft.expect(ev("INTERVAL '3' YEAR * -2")).to_equal(ym(-72L))
    soft.expect(ev("INTERVAL '3' YEAR * 2.1")).to_equal(ym(75L))
    soft.expect(ev("INTERVAL '7' MONTH / 2.5")).to_equal(ym(2L))
    soft.expect(ev("INTERVAL '3' YEAR / 2.25e-1")).to_equal(ym(160L))
    soft.expect(ev("INTERVAL '2' DAY / 3")).to_equal(dt(16L * 3600L, 0L))
    soft
    .expect(ev("INTERVAL '2' DAY * 2.1"))
    .to_equal(dt(4L * 86400L + 4L * 3600L + 48L * 60L, 0L))
    soft
    .expect(ev("INTERVAL '10.5' SECOND / -3"))
    .to_equal(dt(-3L, -500000000L))
    soft
    .expect(ev("INTERVAL '5' MINUTE / 2.25e-1"))
    .to_equal(dt(1333L, 333333000L))
    soft.expect(ev("INTERVAL '3' YEAR * NULL")).to_equal(Null)
    soft.expect(ev("MISSING * INTERVAL '3' YEAR")).to_equal(Missing)
    soft.expect(ev("INTERVAL '3' YEAR / MISSING")).to_equal(Missing)
    soft.expect(ev("INTERVAL '3' YEAR + 1")).to_equal(Missing)
    soft.expect(ev("INTERVAL '3' YEAR + INTERVAL '1' DAY")).to_equal(Missing)
    soft.expect(ev("INTERVAL '3' YEAR * INTERVAL '1' DAY")).to_equal(Missing)
    soft.expect(ev("2 / INTERVAL '1' DAY")).to_equal(Missing)
  })
  for
    source in [
      "INTERVAL '2' DAY / 0", "INTERVAL '2' DAY / 0.0", "INTERVAL '2' DAY / 0e0",
    ] {
    for mode in [@eval.Mode::Permissive, Strict] {
      @expect.expect_call(() => ev(source, mode~)).to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError for \{source}",
      )
    }
  }
}

///|
test "comparison of datetimes and intervals" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("TIME '10:30:00' = TIME '10:30:00+00:00'"))
    .to_equal(Bool(true))
    soft
    .expect(ev("TIME '10:30:00' = TIME '10:30:00+05:00'"))
    .to_equal(Bool(false))
    soft
    .expect(ev("TIME '10:30:00+05:00' < TIME '10:30:00-03:00'"))
    .to_equal(Bool(true))
    soft.expect(ev("TIME '10:30:00' <> TIME '14:45:30'")).to_equal(Bool(true))
    soft
    .expect(ev("DATE '2023-05-15' = TIMESTAMP '2023-05-15 00:00:00'"))
    .to_equal(Bool(true))
    soft
    .expect(ev("DATE '2023-05-15' < TIMESTAMP '2023-05-15 10:30:00+05:00'"))
    .to_equal(Bool(true))
    soft
    .expect(
      ev(
        "TIMESTAMP '2023-05-15 10:00:00+01:00' = TIMESTAMP '2023-05-15 09:00:00+00:00'",
      ),
    )
    .to_equal(Bool(true))
    soft
    .expect(
      ev(
        "TIMESTAMP '2023-05-15 10:30:00' = TIMESTAMP '2023-05-15 10:30:00+05:00'",
      ),
    )
    .to_equal(Bool(false))
    soft
    .expect(
      ev(
        "DATE '2025-01-15' BETWEEN TIMESTAMP '2025-01-01 00:00:00' AND TIMESTAMP '2025-01-31 23:59:59'",
      ),
    )
    .to_equal(Bool(true))
    soft
    .expect(
      ev(
        "TIMESTAMP '2025-02-15 12:00:00' BETWEEN DATE '2025-01-01' AND DATE '2025-01-31'",
      ),
    )
    .to_equal(Bool(false))
    soft
    .expect(ev("INTERVAL '1' YEAR = INTERVAL '12' MONTH"))
    .to_equal(Bool(true))
    soft
    .expect(ev("INTERVAL '1' DAY > INTERVAL '23' HOUR"))
    .to_equal(Bool(true))
    // Different kinds do not compare.
    soft.expect(ev("DATE '2023-05-15' < TIME '10:30:00'")).to_equal(Missing)
    soft.expect(ev("INTERVAL '1' YEAR < INTERVAL '1' DAY")).to_equal(Missing)
    soft
    .expect(ev("INTERVAL '1' YEAR = INTERVAL '1' DAY"))
    .to_equal(Bool(false))
  })
}

///|
test "day-time interval division by a decimal is exact" {
  @expect.expect_all(soft => {
    soft.expect(ev("INTERVAL '1' SECOND / 0.1")).to_equal(dt(10L, 0L))
    soft.expect(ev("INTERVAL '1' DAY / 0.1")).to_equal(dt(10L * 86400L, 0L))
    soft.expect(ev("INTERVAL '1' DAY / -0.1")).to_equal(dt(-10L * 86400L, 0L))
    soft.expect(ev("INTERVAL '2' DAY / 2.25e-1")).to_equal(dt(768000L, 0L))
    soft.expect(ev("INTERVAL '1' DAY / 1e309")).to_equal(dt(0L, 0L))
  })
}

///|
test "scaling an interval has no fixed cap" {
  @expect.expect_all(soft => {
    soft.expect(ev("INTERVAL '500' YEAR(3) * 1")).to_equal(ym(6000L))
    soft.expect(ev("INTERVAL '-1203' MONTH(4) * 1")).to_equal(ym(-1203L))
    soft.expect(ev("INTERVAL '150' DAY(3) / 1")).to_equal(dt(150L * 86400L, 0L))
    soft.expect(ev("INTERVAL '3' YEAR * 50")).to_equal(ym(1800L))
    soft.expect(ev("INTERVAL '2' DAY * 50")).to_equal(dt(100L * 86400L, 0L))
  })
}

///|
fn time_at(
  h : Int,
  m : Int,
  s : Int,
  nanos : Int,
  p : Int,
) -> @value.Value raise Error {
  Time(@value.Time::new(hour=h, minute=m, second=s, nanos~, precision=p))
}

///|
test "an explicit time precision rounds half up" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("TIME (2) '01:23:45.678'"))
    .to_equal(time_at(1, 23, 45, 680000000, 2))
    soft
    .expect(ev("TIME (2) '12:00:00.129'"))
    .to_equal(time_at(12, 0, 0, 130000000, 2))
    soft
    .expect(ev("TIME (2) '12:00:00.124'"))
    .to_equal(time_at(12, 0, 0, 120000000, 2))
    soft.expect(ev("TIME (0) '12:00:00.9'")).to_equal(time_at(12, 0, 1, 0, 0))
    soft.expect(ev("TIME (0) '12:59:59.5'")).to_equal(time_at(13, 0, 0, 0, 0))
    soft.expect(ev("TIME (2) '23:59:59.999'")).to_equal(time_at(0, 0, 0, 0, 2))
    soft
    .expect(ev("TIME '23:59:59.999999999999'"))
    .to_equal(time_at(23, 59, 59, 999999999, 9))
    soft
    .expect(ev("TIMESTAMP (1) '2024-12-31 23:59:59.96'"))
    .to_equal(
      Timestamp(
        @value.Timestamp::new(
          @value.Date::new(year=2025, month=1, day=1),
          @value.Time::new(hour=0, minute=0, second=0, precision=1),
        ),
      ),
    )
  })
}
