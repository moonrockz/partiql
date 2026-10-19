///|
fn iq(
  start : @ast.DatetimeField,
  end : @ast.DatetimeField?,
  leading? : Int32,
  fraction? : Int32,
) -> CastTarget {
  Interval({
    start,
    start_precision: leading,
    end,
    fractional_precision: fraction,
  })
}

///|
/// Total, so that a `failure` closure may call it: a bad input gives MISSING.
fn months(n : Int64) -> @value.Value {
  try @value.Value::from_interval_ym(@value.IntervalYM(n)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
fn span_of(seconds : Int64, nanos : Int64) -> @value.Value {
  try @value.Value::from_interval_dt(@value.IntervalDT(seconds, nanos)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
test "interval to interval" {
  @expect.expect_all(soft => {
    soft
    .expect(cast(months(12), iq(Year, None, leading=3)))
    .to_equal(months(12))
    soft.expect(cast(months(13), iq(Year, Some(Month)))).to_equal(months(13))
    soft.expect(cast(months(13), iq(Year, None))).to_equal(months(12))
    soft.expect(cast(months(-13), iq(Year, None))).to_equal(months(-12))
    soft
    .expect(failure(() => cast(months(100 * 12), iq(Year, None))))
    .to_equal("data")
    soft
    .expect(failure(() => cast(months(100), iq(Month, None))))
    .to_equal("data")
    soft
    .expect(cast(span_of(25 * 3600, 0), iq(Day, Some(Hour))))
    .to_equal(span_of(25 * 3600, 0))
    soft
    .expect(cast(span_of(3661, 0), iq(Hour, None)))
    .to_equal(span_of(3600, 0))
    soft
    .expect(cast(span_of(1, 123456789), iq(Second, None, fraction=3)))
    .to_equal(span_of(1, 123000000))
    soft
    .expect(failure(() => cast(span_of(100 * 86400, 0), iq(Day, None))))
    .to_equal("data")
    soft.expect(failure(() => cast(months(1), iq(Day, None)))).to_equal("type")
    soft
    .expect(failure(() => cast(span_of(1, 0), iq(Year, None))))
    .to_equal("type")
  })
}

///|
test "text and numbers to interval" {
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_string(" 1-2 "), iq(Year, Some(Month))))
    .to_equal(months(14))
    soft
    .expect(
      cast(@value.Value::from_string("3 04:05:06.5"), iq(Day, Some(Second))),
    )
    .to_equal(span_of(273906, 500000000))
    soft
    .expect(
      failure(() => cast(@value.Value::from_string("100"), iq(Day, None))),
    )
    .to_equal("data")
    soft
    .expect(failure(() => cast(@value.Value::from_string("x"), iq(Day, None))))
    .to_equal("type")
    soft
    .expect(cast(@value.Value::from_int(3), iq(Day, None)))
    .to_equal(span_of(3 * 86400, 0))
    soft
    .expect(cast(@value.Value::from_int(-2), iq(Year, None)))
    .to_equal(months(-24))
    soft
    .expect(cast(dec_value("1.7"), iq(Day, None)))
    .to_equal(span_of(86400, 0))
    soft.expect(cast(dec_value("1.5"), iq(Year, None))).to_equal(months(12))
    soft
    .expect(cast(dec_value("1.25"), iq(Second, None)))
    .to_equal(span_of(1, 250000000))
    soft
    .expect(failure(() => cast(@value.Value::from_int(100), iq(Day, None))))
    .to_equal("data")
    soft
    .expect(failure(() => cast(@value.Value::from_int(1), iq(Day, Some(Hour)))))
    .to_equal("type")
    soft
    .expect(failure(() => cast(@value.Value::from_float(1.0), iq(Day, None))))
    .to_equal("type")
    soft
    .expect(failure(() => cast(@value.Value::from_bool(true), iq(Day, None))))
    .to_equal("type")
    soft
    .expect(failure(() => cast(dec_value("1d2000000000"), iq(Day, None))))
    .to_equal("data")
  })
}

///|
fn dec_value(text : String) -> @value.Value {
  try @value.Value::from_decimal(@ion_core.Decimal::parse(text)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}
