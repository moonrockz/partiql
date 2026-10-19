///|
fn qualifier(
  start : @ast.DatetimeField,
  end : @ast.DatetimeField?,
) -> @ast.IntervalQualifier {
  { start, start_precision: None, end, fractional_precision: None, }
}

///|
test "literal parsers in ops" {
  @expect.expect_all(soft => {
    soft
    .expect(parse_date("2020-02-29"))
    .to_equal(@value.Date::Date(year=2020, month=2, day=29))
    soft
    .expect(failure(() => @value.Value::from_date(parse_date("2021-02-29"))))
    .to_equal("type")
    soft
    .expect(parse_time("12:00:00.123+05:30", None, false))
    .to_equal(
      @value.Time::Time(
        hour=12,
        minute=0,
        second=0,
        nanos=123000000,
        precision=3,
        offset=Some(330),
      ),
    )
    soft
    .expect(
      failure(() => @value.Value::from_time(parse_time("12:00:00", None, true))),
    )
    .to_equal("type")
    soft
    .expect(
      parse_interval(
        "1-2",
        negative=false,
        qualifier=qualifier(Year, Some(Month)),
      ),
    )
    .to_equal(@value.Value::from_interval_ym(@value.IntervalYM(14L)))
    soft
    .expect(interval_qualifier_valid(qualifier(Day, Some(Second))))
    .to_be_true()
    soft
    .expect(interval_qualifier_valid(qualifier(Month, Some(Year))))
    .to_be_false()
    soft
    .expect(interval_qualifier_valid(qualifier(Year, Some(Day))))
    .to_be_false()
  })
}
