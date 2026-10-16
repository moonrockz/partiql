///|
fn ex(
  field : @ast.DatetimeField,
  x : @value.Value,
) -> @value.Value raise OpFailure {
  extract(field, [x])
}

///|
fn stamp(date : @value.Date, time : @value.Time) -> @value.Value {
  Timestamp(@value.Timestamp::new(date, time))
}

///|
test "EXTRACT from dates, times and timestamps" {
  let d = day_of(2024, 2, 29)
  let t = tm(13, 4, 5, 678000000, 3, Some(-390))
  let no_zone = tm(1, 23, 45, 0, 1, None)
  @expect.expect_all(soft => {
    soft.expect(ex(Year, Date(d))).to_equal(Int(2024))
    soft.expect(ex(Month, Date(d))).to_equal(Int(2))
    soft.expect(ex(Day, Date(d))).to_equal(Int(29))
    soft.expect(failure(() => ex(Hour, Date(d)))).to_equal("type")
    soft.expect(failure(() => ex(Second, Date(d)))).to_equal("type")
    soft.expect(failure(() => ex(TimezoneHour, Date(d)))).to_equal("type")
    soft.expect(ex(Hour, Time(t))).to_equal(Int(13))
    soft.expect(ex(Minute, Time(t))).to_equal(Int(4))
    soft.expect(ex(Second, Time(t))).to_equal(dn("5.678"))
    soft.expect(ex(Second, Time(no_zone))).to_equal(dn("45.0"))
    soft.expect(ex(TimezoneHour, Time(t))).to_equal(Int(-6))
    soft.expect(ex(TimezoneMinute, Time(t))).to_equal(Int(-30))
    soft.expect(failure(() => ex(TimezoneHour, Time(no_zone)))).to_equal("type")
    soft.expect(failure(() => ex(Year, Time(t)))).to_equal("type")
    let ts = stamp(d, tm(3, 4, 5, 670000000, 2, Some(489)))
    soft.expect(ex(Year, ts)).to_equal(Int(2024))
    soft.expect(ex(Hour, ts)).to_equal(Int(3))
    soft.expect(ex(Second, ts)).to_equal(dn("5.67"))
    soft.expect(ex(TimezoneHour, ts)).to_equal(Int(8))
    soft.expect(ex(TimezoneMinute, ts)).to_equal(Int(9))
  })
}

///|
test "EXTRACT from intervals" {
  let ym = @value.Value::IntervalYM(@value.IntervalYM::new(-14L))
  let dt = @value.Value::IntervalDT(
    @value.IntervalDT::new(
      -(3L * 86400L + 4L * 3600L + 5L * 60L + 6L),
      -780000000L,
    ),
  )
  let fine = @value.Value::IntervalDT(@value.IntervalDT::new(1L, 123456789L))
  @expect.expect_all(soft => {
    soft.expect(ex(Year, ym)).to_equal(Int(-1))
    soft.expect(ex(Month, ym)).to_equal(Int(-2))
    soft.expect(failure(() => ex(Day, ym))).to_equal("type")
    soft.expect(ex(Day, dt)).to_equal(Int(-3))
    soft.expect(ex(Hour, dt)).to_equal(Int(-4))
    soft.expect(ex(Minute, dt)).to_equal(Int(-5))
    soft.expect(ex(Second, dt)).to_equal(dn("-6.780000"))
    soft.expect(ex(Second, fine)).to_equal(dn("1.123456789"))
    soft.expect(failure(() => ex(Year, dt))).to_equal("type")
    soft.expect(failure(() => ex(TimezoneHour, dt))).to_equal("type")
  })
}

///|
test "EXTRACT: absent values, wrong kinds and Ion" {
  let ion = @value.Value::Ion(
    @ion_core.IonValue::timestamp(@ion_core.Timestamp::new(year=2017)),
  )
  @expect.expect_all(soft => {
    soft.expect(ex(Year, Null)).to_equal(Null)
    soft.expect(ex(Year, Missing)).to_equal(Missing)
    soft.expect(failure(() => ex(Year, Int(1)))).to_equal("type")
    soft.expect(failure(() => ex(Year, String("2020-01-01")))).to_equal("type")
    soft.expect(ex(Year, ion)).to_equal(Int(2017))
    soft.expect(ex(TimezoneHour, ion)).to_equal(Int(0))
  })
}
