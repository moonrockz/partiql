///|
/// A date value for use inside a `failure` closure.
fn date_on(year : Int32, month : Int32, day : Int32) -> @value.Value {
  try @value.Value::from_date(@value.Date(year~, month~, day~)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
fn ym_of(months : Int64) -> @value.Value {
  try @value.Value::from_interval_ym(@value.IntervalYM(months)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
fn days_of(n : Int64) -> @value.Value {
  try @value.Value::from_interval_dt(@value.IntervalDT(n * 86400L, 0L)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
test "a year-month step onto a missing day is a datetime field overflow" {
  @expect.expect_all(soft => {
    soft
    .expect(failure(() => add(date_on(2025, 1, 31), ym_of(1L))))
    .to_equal("data")
    soft
    .expect(failure(() => add(date_on(2024, 2, 29), ym_of(12L))))
    .to_equal("data")
    soft
    .expect(failure(() => sub(date_on(2025, 3, 31), ym_of(1L))))
    .to_equal("data")
    soft
    .expect(add(date_on(2025, 1, 28), ym_of(1L)))
    .to_equal(date_on(2025, 2, 28))
    soft
    .expect(add(date_on(2024, 2, 29), ym_of(48L)))
    .to_equal(date_on(2028, 2, 29))
    soft
    .expect(add(date_on(2025, 1, 30), ym_of(2L)))
    .to_equal(date_on(2025, 3, 30))
  })
}

///|
test "datetime results stay in years 0001-9999" {
  @expect.expect_all(soft => {
    soft
    .expect(add(date_on(9999, 12, 31), days_of(0L)))
    .to_equal(date_on(9999, 12, 31))
    soft
    .expect(failure(() => add(date_on(9999, 12, 31), days_of(1L))))
    .to_equal("data")
    soft
    .expect(failure(() => sub(date_on(1, 1, 1), days_of(1L))))
    .to_equal("data")
    soft
    .expect(failure(() => add(date_on(9999, 1, 1), ym_of(12L))))
    .to_equal("data")
    soft
    .expect(failure(() => sub(date_on(1, 6, 1), ym_of(12L))))
    .to_equal("data")
    soft.expect(add(date_on(1, 1, 1), days_of(1L))).to_equal(date_on(1, 1, 2))
  })
}

///|
test "literal and CAST text years outside 0001-9999 are not valid" {
  @expect.expect_all(soft => {
    soft
    .expect(failure(() => @value.Value::from_date(parse_date("10000-01-01"))))
    .to_equal("type")
    soft
    .expect(failure(() => @value.Value::from_date(parse_date("0000-01-01"))))
    .to_equal("type")
    soft
    .expect(failure(() => @value.Value::from_date(parse_date("-0001-01-01"))))
    .to_equal("type")
    soft
    .expect(parse_date("0001-01-01"))
    .to_equal(@value.Date::Date(year=1, month=1, day=1))
  })
}

///|
test "CAST of a datetime value outside the range is a data failure" {
  // Values read from data keep the value model's range; a CAST result is
  // checked.
  let wide = date_on(19998, 1, 1)
  @expect.expect_all(soft => {
    soft.expect(failure(() => cast(wide, Date))).to_equal("data")
    soft
    .expect(failure(() => cast(wide, Timestamp(precision=None, zone=false))))
    .to_equal("data")
  })
}
