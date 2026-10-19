///|
fn sort_values(
  values : Array[@value.Value],
  nulls : @value.NullOrder,
) -> Array[@value.Value] {
  let out = values.copy()
  out.sort_by((a, b) => @value.compare(a, b, nulls~))
  out
}

///|
test "rank of kinds" {
  let date = @value.Date::Date(year=2024, month=1, day=1)
  let time = @value.Time::Time(hour=1, minute=0, second=0)
  let values : Array[@value.Value] = [
    @value.Value::from_bag(@value.Bag([])),
    @value.Value::from_tuple(@value.Tuple([])),
    @value.Value::from_list([]),
    @value.Value::from_blob(b""),
    @value.Value::from_string(""),
    @value.Value::from_interval_dt(@value.IntervalDT(0L, 0L)),
    @value.Value::from_interval_ym(@value.IntervalYM(0L)),
    @value.Value::from_timestamp(@value.Timestamp(date, time)),
    @value.Value::from_time(time),
    @value.Value::from_date(date),
    i(0),
    @value.Value::from_bool(true),
    @value.Value::Null,
  ]
  let sorted = sort_values(values, NullsFirst)
  @expect.expect(sorted == values.rev()).to_be_true()
}

///|
test "nulls first or last; NULL and MISSING are equal" {
  @expect.expect_all(soft => {
    soft
    .expect(@value.compare(@value.Value::Null, i(1), nulls=NullsFirst))
    .to_equal(-1)
    soft
    .expect(@value.compare(@value.Value::Null, i(1), nulls=NullsLast))
    .to_equal(1)
    soft
    .expect(
      @value.compare(
        @value.Value::Null,
        @value.Value::Missing,
        nulls=NullsFirst,
      ),
    )
    .to_equal(0)
    // Nested: equal for ordering, but not eqg.
    let a = @value.Value::from_list([@value.Value::Null])
    let b = @value.Value::from_list([@value.Value::Missing])
    soft.expect(@value.compare(a, b, nulls=NullsFirst)).to_equal(0)
    soft.expect(@value.eqg(a, b)).to_be_false()
  })
}

///|
test "numbers order by value across types" {
  let values : Array[@value.Value] = [
    @value.Value::from_float(@double.infinity),
    @value.Value::from_decimal(@ion_core.Decimal::Decimal(15N, -1)),
    i(1),
    @value.Value::from_float(@double.neg_infinity),
    @value.Value::from_float(@double.not_a_number),
  ]
  @expect.expect(sort_values(values, NullsFirst) == values.rev()).to_be_true()
}

///|
test "text by code point; lists lexicographic; bags sorted" {
  @expect.expect_all(soft => {
    soft
    .expect(
      @value.compare(
        @value.Value::from_string("b"),
        @value.Value::from_string("aa"),
        nulls=NullsFirst,
      ),
    )
    .to_equal(1)
    soft
    .expect(
      @value.compare(
        @value.Value::from_list([i(1)]),
        @value.Value::from_list([i(1), i(0)]),
        nulls=NullsFirst,
      ),
    )
    .to_equal(-1)
    let b1 = @value.Value::from_bag(@value.Bag([i(2), i(1)]))
    let b2 = @value.Value::from_bag(@value.Bag([i(1), i(3)]))
    soft.expect(@value.compare(b1, b2, nulls=NullsFirst)).to_equal(-1)
  })
}

///|
test "without time zone sorts first at equal fields" {
  @expect.expect_all(soft => {
    let date = @value.Date::Date(year=2024, month=1, day=1)
    let local_ts = @value.Value::from_timestamp(
      @value.Timestamp(date, @value.Time::Time(hour=0, minute=0, second=0)),
    )
    let utc = @value.Value::from_timestamp(
      @value.Timestamp(
        date,
        @value.Time::Time(hour=0, minute=0, second=0, offset=Some(0)),
      ),
    )
    soft.expect(@value.compare(local_ts, utc, nulls=NullsFirst)).to_equal(-1)
    soft.expect(@value.compare(utc, local_ts, nulls=NullsFirst)).to_equal(1)
  })
}
