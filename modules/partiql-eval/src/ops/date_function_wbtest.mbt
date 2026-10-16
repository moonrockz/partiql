///|
fn add_of(
  field : @ast.DatetimeField,
  n : @value.Value,
  x : @value.Value,
) -> @value.Value raise OpFailure {
  date_add(field, [n, x])
}

///|
/// A timestamp value for use inside a `failure` closure.
fn at(
  year : Int32,
  month : Int32,
  day : Int32,
  hour : Int32,
  nanos : Int32,
  precision : Int32,
  offset : Int32?,
) -> @value.Value {
  try
    @value.Value::Timestamp(
      @value.Timestamp::new(
        @value.Date::new(year~, month~, day~),
        @value.Time::new(hour~, minute=0, second=0, nanos~, precision~, offset~),
      ),
    )
  catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
fn on_day(year : Int32, month : Int32, day : Int32) -> @value.Value {
  try @value.Value::Date(@value.Date::new(year~, month~, day~)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
fn clock_at(hour : Int32, minute : Int32) -> @value.Value {
  try
    @value.Value::Time(@value.Time::new(hour~, minute~, second=0, precision=0))
  catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
test "DATE_ADD by field and type" {
  @expect.expect_all(soft => {
    soft
    .expect(add_of(Year, Int(1), on_day(2024, 2, 28)))
    .to_equal(on_day(2025, 2, 28))
    soft
    .expect(add_of(Month, Int(-2), on_day(2025, 3, 31)))
    .to_equal(on_day(2025, 1, 31))
    soft
    .expect(add_of(Day, Int(1), on_day(2024, 2, 28)))
    .to_equal(on_day(2024, 2, 29))
    soft
    .expect(failure(() => add_of(Hour, Int(1), on_day(2024, 2, 28))))
    .to_equal("type")
    soft.expect(add_of(Hour, Int(2), clock_at(23, 0))).to_equal(clock_at(1, 0))
    soft
    .expect(add_of(Minute, Int(-30), clock_at(0, 15)))
    .to_equal(clock_at(23, 45))
    soft
    .expect(failure(() => add_of(Day, Int(1), clock_at(1, 0))))
    .to_equal("type")
    soft
    .expect(add_of(Second, Int(36288000), at(2017, 1, 1, 0, 0, 0, Some(0))))
    .to_equal(at(2018, 2, 25, 0, 0, 0, Some(0)))
    // Precision and offset are kept.
    soft
    .expect(add_of(Hour, Int(1), at(2020, 1, 1, 23, 500000000, 3, Some(330))))
    .to_equal(at(2020, 1, 2, 0, 500000000, 3, Some(330)))
  })
}

///|
test "DATE_ADD failures" {
  let huge = @value.Value::BigInt(
    @bigint.BigInt::from_string("99999999999999999999"),
  )
  @expect.expect_all(soft => {
    soft
    .expect(failure(() => add_of(Month, Int(1), on_day(2025, 1, 31))))
    .to_equal("data")
    soft
    .expect(failure(() => add_of(Year, Int(1), on_day(9999, 6, 1))))
    .to_equal("data")
    soft
    .expect(failure(() => add_of(Day, huge, on_day(2020, 1, 1))))
    .to_equal("data")
    soft
    .expect(failure(() => add_of(Year, huge, on_day(2020, 1, 1))))
    .to_equal("data")
    soft
    .expect(failure(() => add_of(Day, dn("1.5"), on_day(2020, 1, 1))))
    .to_equal("type")
    soft
    .expect(failure(() => add_of(Day, Int(1), String("2020-01-01"))))
    .to_equal("type")
    soft.expect(add_of(Day, Null, Missing)).to_equal(Missing)
    soft.expect(add_of(Day, Null, on_day(2020, 1, 1))).to_equal(Null)
    soft.expect(failure(() => add_of(Day, String("1"), Null))).to_equal("type")
  })
}

///|
fn diff_of(
  field : @ast.DatetimeField,
  a : @value.Value,
  b : @value.Value,
  zone~ : ZoneOffset = ZoneOffset::utc(),
) -> @value.Value raise OpFailure {
  date_diff(field, [a, b], zone~)
}

///|
test "DATE_DIFF day to second: elapsed units toward zero" {
  @expect.expect_all(soft => {
    // date_diff.ion:2287 and :1538.
    soft
    .expect(diff_of(Hour, on_day(2025, 1, 15), at(2025, 1, 14, 12, 0, 0, None)))
    .to_equal(Int(-12))
    soft
    .expect(
      diff_of(
        Day,
        at(2017, 1, 2, 1, 0, 0, Some(600)),
        at(2017, 1, 2, 1, 0, 0, Some(0)),
      ),
    )
    .to_equal(Int(0))
    soft
    .expect(
      diff_of(
        Hour,
        at(2017, 1, 2, 1, 0, 0, Some(600)),
        at(2017, 1, 2, 1, 0, 0, Some(0)),
      ),
    )
    .to_equal(Int(10))
    soft
    .expect(diff_of(Day, on_day(2016, 2, 1), on_day(2016, 3, 1)))
    .to_equal(Int(29))
    soft
    .expect(diff_of(Minute, clock_at(8, 15), clock_at(6, 0)))
    .to_equal(Int(-135))
    soft
    .expect(failure(() => diff_of(Day, clock_at(8, 15), clock_at(6, 0))))
    .to_equal("type")
    soft
    .expect(failure(() => diff_of(Hour, clock_at(8, 15), on_day(2020, 1, 1))))
    .to_equal("type")
  })
}

///|
test "DATE_DIFF months and years count complete months" {
  @expect.expect_all(soft => {
    soft
    .expect(diff_of(Month, on_day(2025, 1, 31), on_day(2025, 2, 28)))
    .to_equal(Int(0))
    soft
    .expect(diff_of(Month, on_day(2025, 1, 15), on_day(2025, 3, 15)))
    .to_equal(Int(2))
    soft
    .expect(diff_of(Month, on_day(2025, 3, 15), on_day(2025, 1, 16)))
    .to_equal(Int(-1))
    soft
    .expect(diff_of(Month, on_day(2025, 3, 15), on_day(2025, 1, 15)))
    .to_equal(Int(-2))
    soft
    .expect(diff_of(Year, on_day(2020, 2, 29), on_day(2021, 2, 28)))
    .to_equal(Int(0))
    soft
    .expect(diff_of(Year, on_day(2020, 2, 29), on_day(2024, 2, 29)))
    .to_equal(Int(4))
    soft
    .expect(
      diff_of(
        Month,
        at(2025, 1, 15, 12, 0, 0, None),
        at(2025, 2, 15, 11, 0, 0, None),
      ),
    )
    .to_equal(Int(0))
  })
}

///|
test "DATE_DIFF puts values without an offset in the session zone" {
  let plus_two = zone_of(120)
  @expect.expect_all(soft => {
    // 00:00 local at +02:00 is 22:00 UTC the day before.
    soft
    .expect(
      diff_of(
        Hour,
        at(2020, 1, 1, 0, 0, 0, None),
        at(2020, 1, 1, 0, 0, 0, Some(0)),
        zone=plus_two,
      ),
    )
    .to_equal(Int(2))
    soft
    .expect(
      diff_of(
        Hour,
        at(2020, 1, 1, 0, 0, 0, None),
        at(2020, 1, 1, 0, 0, 0, Some(0)),
      ),
    )
    .to_equal(Int(0))
  })
}

///|
test "DATE_DIFF months: wide data years and the year range" {
  @expect.expect_all(soft => {
    // Years from data may exceed Int32 arithmetic when multiplied by 12.
    soft
    .expect(diff_of(Month, on_day(999999999, 1, 1), on_day(2000, 1, 1)))
    .to_equal(Int(-11999975988L))
    // The result is an integer: the 0001-9999 rule for datetime results does
    // not apply to the values compared.
    soft
    .expect(diff_of(Month, on_day(19998, 1, 1), on_day(19998, 3, 1)))
    .to_equal(Int(2))
    soft
    .expect(
      diff_of(
        Month,
        at(2000, 1, 1, 0, 0, 0, Some(300)),
        at(9999, 12, 31, 23, 0, 0, Some(-300)),
      ),
    )
    .to_equal(Int(96000))
  })
}
