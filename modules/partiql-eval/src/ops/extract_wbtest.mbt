///|
fn ex(
  field : @ast.DatetimeField,
  x : @value.Value,
) -> @value.Value raise OpFailure {
  extract(field, [x])
}

///|
fn stamp(date : @value.Date, time : @value.Time) -> @value.Value {
  @value.Value::from_timestamp(@value.Timestamp(date, time))
}

///|
test "EXTRACT from dates, times and timestamps" {
  let d = day_of(2024, 2, 29)
  let t = tm(13, 4, 5, 678000000, 3, Some(-390))
  let no_zone = tm(1, 23, 45, 0, 1, None)
  @expect.expect_all(soft => {
    soft
    .expect(ex(Year, @value.Value::from_date(d)))
    .to_equal(@value.Value::from_int(2024))
    soft
    .expect(ex(Month, @value.Value::from_date(d)))
    .to_equal(@value.Value::from_int(2))
    soft
    .expect(ex(Day, @value.Value::from_date(d)))
    .to_equal(@value.Value::from_int(29))
    soft
    .expect(failure(() => ex(Hour, @value.Value::from_date(d))))
    .to_equal("type")
    soft
    .expect(failure(() => ex(Second, @value.Value::from_date(d))))
    .to_equal("type")
    soft
    .expect(failure(() => ex(TimezoneHour, @value.Value::from_date(d))))
    .to_equal("type")
    soft
    .expect(ex(Hour, @value.Value::from_time(t)))
    .to_equal(@value.Value::from_int(13))
    soft
    .expect(ex(Minute, @value.Value::from_time(t)))
    .to_equal(@value.Value::from_int(4))
    soft.expect(ex(Second, @value.Value::from_time(t))).to_equal(dn("5.678"))
    soft
    .expect(ex(Second, @value.Value::from_time(no_zone)))
    .to_equal(dn("45.0"))
    soft
    .expect(ex(TimezoneHour, @value.Value::from_time(t)))
    .to_equal(@value.Value::from_int(-6))
    soft
    .expect(ex(TimezoneMinute, @value.Value::from_time(t)))
    .to_equal(@value.Value::from_int(-30))
    soft
    .expect(failure(() => ex(TimezoneHour, @value.Value::from_time(no_zone))))
    .to_equal("type")
    soft
    .expect(failure(() => ex(Year, @value.Value::from_time(t))))
    .to_equal("type")
    let ts = stamp(d, tm(3, 4, 5, 670000000, 2, Some(489)))
    soft.expect(ex(Year, ts)).to_equal(@value.Value::from_int(2024))
    soft.expect(ex(Hour, ts)).to_equal(@value.Value::from_int(3))
    soft.expect(ex(Second, ts)).to_equal(dn("5.67"))
    soft.expect(ex(TimezoneHour, ts)).to_equal(@value.Value::from_int(8))
    soft.expect(ex(TimezoneMinute, ts)).to_equal(@value.Value::from_int(9))
  })
}

///|
test "EXTRACT from intervals" {
  let ym = @value.Value::from_interval_ym(@value.IntervalYM(-14L))
  let dt = @value.Value::from_interval_dt(
    @value.IntervalDT(-(3L * 86400L + 4L * 3600L + 5L * 60L + 6L), -780000000L),
  )
  let fine = @value.Value::from_interval_dt(@value.IntervalDT(1L, 123456789L))
  @expect.expect_all(soft => {
    soft.expect(ex(Year, ym)).to_equal(@value.Value::from_int(-1))
    soft.expect(ex(Month, ym)).to_equal(@value.Value::from_int(-2))
    soft.expect(failure(() => ex(Day, ym))).to_equal("type")
    soft.expect(ex(Day, dt)).to_equal(@value.Value::from_int(-3))
    soft.expect(ex(Hour, dt)).to_equal(@value.Value::from_int(-4))
    soft.expect(ex(Minute, dt)).to_equal(@value.Value::from_int(-5))
    soft.expect(ex(Second, dt)).to_equal(dn("-6.780000"))
    soft.expect(ex(Second, fine)).to_equal(dn("1.123456789"))
    soft.expect(failure(() => ex(Year, dt))).to_equal("type")
    soft.expect(failure(() => ex(TimezoneHour, dt))).to_equal("type")
  })
}

///|
test "EXTRACT: absent values, wrong kinds and Ion" {
  let ion = @value.Value::from_ion(
    @ion_core.IonValue::timestamp(@ion_core.Timestamp::Timestamp(year=2017)),
  )
  @expect.expect_all(soft => {
    soft.expect(ex(Year, Null)).to_equal(Null)
    soft.expect(ex(Year, Missing)).to_equal(Missing)
    soft
    .expect(failure(() => ex(Year, @value.Value::from_int(1))))
    .to_equal("type")
    soft
    .expect(failure(() => ex(Year, @value.Value::from_string("2020-01-01"))))
    .to_equal("type")
    soft.expect(ex(Year, ion)).to_equal(@value.Value::from_int(2017))
    soft.expect(ex(TimezoneHour, ion)).to_equal(@value.Value::from_int(0))
  })
}
