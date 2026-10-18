///|
fn tm(
  hour : Int32,
  minute : Int32,
  second : Int32,
  nanos : Int32,
  precision : Int32,
  offset : Int32?,
) -> @value.Time raise {
  @value.Time::Time(hour~, minute~, second~, nanos~, precision~, offset~)
}

///|
fn day_of(year : Int32, month : Int32, day : Int32) -> @value.Date raise {
  @value.Date::Date(year~, month~, day~)
}

///|
fn zone_of(minutes : Int32) -> ZoneOffset {
  ZoneOffset::from_minutes(minutes).unwrap_or(ZoneOffset::utc())
}

///|
let plain_time : CastTarget = Time(precision=None, zone=false)

///|
let zoned_time_target : CastTarget = Time(precision=None, zone=true)

///|
let plain_stamp : CastTarget = Timestamp(precision=None, zone=false)

///|
test "ZoneOffset range" {
  @expect.expect_all(soft => {
    soft.expect(ZoneOffset::from_minutes(1080) is Some(_)).to_be_true()
    soft.expect(ZoneOffset::from_minutes(-1080) is Some(_)).to_be_true()
    soft.expect(ZoneOffset::from_minutes(1081) is None).to_be_true()
  })
}

///|
test "cast to DATE" {
  let stamp = @value.Timestamp::Timestamp(
    day_of(2020, 1, 1),
    tm(23, 0, 0, 0, 0, Some(0)),
  )
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_date(day_of(2020, 1, 1)), Date))
    .to_equal(@value.Value::from_date(day_of(2020, 1, 1)))
    soft
    .expect(cast(@value.Value::from_timestamp(stamp), Date, zone=zone_of(330)))
    .to_equal(@value.Value::from_date(day_of(2020, 1, 2)))
    soft
    .expect(cast(@value.Value::from_timestamp(stamp), Date))
    .to_equal(@value.Value::from_date(day_of(2020, 1, 1)))
    soft
    .expect(cast(@value.Value::from_string(" 2020-02-29 "), Date))
    .to_equal(@value.Value::from_date(day_of(2020, 2, 29)))
    soft
    .expect(failure(() => cast(@value.Value::from_string("2021-02-29"), Date)))
    .to_equal("type")
    soft
    .expect(failure(() => cast(@value.Value::from_int(1), Date)))
    .to_equal("type")
  })
}

///|
test "cast to TIME: precision and zones" {
  @expect.expect_all(soft => {
    soft
    .expect(
      cast(
        @value.Value::from_time(tm(12, 34, 56, 789000000, 3, None)),
        Time(precision=Some(1), zone=false),
      ),
    )
    .to_equal(@value.Value::from_time(tm(12, 34, 56, 800000000, 1, None)))
    soft
    .expect(
      cast(
        @value.Value::from_time(tm(23, 59, 59, 999900000, 4, None)),
        Time(precision=Some(3), zone=false),
      ),
    )
    .to_equal(@value.Value::from_time(tm(0, 0, 0, 0, 3, None)))
    soft
    .expect(
      cast(
        @value.Value::from_time(tm(12, 0, 0, 0, 0, None)),
        zoned_time_target,
        zone=zone_of(330),
      ),
    )
    .to_equal(@value.Value::from_time(tm(12, 0, 0, 0, 0, Some(330))))
    soft
    .expect(
      cast(@value.Value::from_time(tm(12, 0, 0, 0, 0, Some(60))), plain_time),
    )
    .to_equal(@value.Value::from_time(tm(11, 0, 0, 0, 0, None)))
    soft
    .expect(
      cast(
        @value.Value::from_time(tm(1, 0, 0, 0, 0, Some(60))),
        plain_time,
        zone=zone_of(-480),
      ),
    )
    .to_equal(@value.Value::from_time(tm(16, 0, 0, 0, 0, None)))
    soft
    .expect(
      cast(
        @value.Value::from_time(tm(12, 0, 0, 0, 0, Some(60))),
        zoned_time_target,
        zone=zone_of(330),
      ),
    )
    .to_equal(@value.Value::from_time(tm(12, 0, 0, 0, 0, Some(60))))
    let stamp = @value.Timestamp::Timestamp(
      day_of(2020, 1, 1),
      tm(12, 0, 0, 500000000, 1, None),
    )
    soft
    .expect(cast(@value.Value::from_timestamp(stamp), plain_time))
    .to_equal(@value.Value::from_time(tm(12, 0, 0, 500000000, 1, None)))
    soft
    .expect(cast(@value.Value::from_string("12:00:00+02:00"), plain_time))
    .to_equal(@value.Value::from_time(tm(10, 0, 0, 0, 1, None)))
    soft
    .expect(
      failure(() => cast(@value.Value::from_string("25:00:00"), plain_time)),
    )
    .to_equal("type")
    let new_year = @value.Value::from_date(day_of(2020, 1, 1))
    soft.expect(failure(() => cast(new_year, plain_time))).to_equal("type")
  })
}

///|
test "cast to TIMESTAMP: dates, carry and zones" {
  let midnight = tm(0, 0, 0, 0, 0, None)
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_date(day_of(2020, 1, 1)), plain_stamp))
    .to_equal(
      @value.Value::from_timestamp(
        @value.Timestamp(day_of(2020, 1, 1), midnight),
      ),
    )
    soft
    .expect(
      cast(
        @value.Value::from_date(day_of(2020, 1, 1)),
        Timestamp(precision=None, zone=true),
        zone=zone_of(-480),
      ),
    )
    .to_equal(
      @value.Value::from_timestamp(
        @value.Timestamp(day_of(2020, 1, 1), tm(0, 0, 0, 0, 0, Some(-480))),
      ),
    )
    let late = @value.Timestamp::Timestamp(
      day_of(2026, 12, 31),
      tm(23, 59, 59, 999900000, 4, None),
    )
    soft
    .expect(
      cast(
        @value.Value::from_timestamp(late),
        Timestamp(precision=Some(3), zone=false),
      ),
    )
    .to_equal(
      @value.Value::from_timestamp(
        @value.Timestamp(day_of(2027, 1, 1), tm(0, 0, 0, 0, 3, None)),
      ),
    )
    let last = @value.Timestamp::Timestamp(
      day_of(9999, 12, 31),
      tm(23, 59, 59, 999900000, 4, None),
    )
    // The carry leaves 0001-9999 (spec M4d3 §5).
    let carried = @value.Value::from_timestamp(last)
    soft
    .expect(
      failure(() => cast(carried, Timestamp(precision=Some(3), zone=false))),
    )
    .to_equal("data")
    let early = @value.Timestamp::Timestamp(
      day_of(2020, 1, 1),
      tm(1, 0, 0, 0, 0, Some(120)),
    )
    soft
    .expect(cast(@value.Value::from_timestamp(early), plain_stamp))
    .to_equal(
      @value.Value::from_timestamp(
        @value.Timestamp(day_of(2019, 12, 31), tm(23, 0, 0, 0, 0, None)),
      ),
    )
    soft
    .expect(failure(() => cast(@value.Value::from_time(midnight), plain_stamp)))
    .to_equal("data")
    soft
    .expect(cast(@value.Value::from_string("2020-01-01T10:00:00"), plain_stamp))
    .to_equal(
      @value.Value::from_timestamp(
        @value.Timestamp(day_of(2020, 1, 1), tm(10, 0, 0, 0, 1, None)),
      ),
    )
  })
}
