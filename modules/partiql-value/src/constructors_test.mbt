///|
test "from_tuple supplies the expected constructor type and preserves fields" {
  let wrapped = @value.Value::from_tuple(
    @value.Tuple([
      ("a", @value.Value(1)),
      ("a", @value.Value(2)),
      ("missing", @value.Value::Missing),
    ]),
  )
  guard wrapped is @value.Value::Tuple(tuple) else {
    fail("expected a tuple value")
  }
  @expect.expect(tuple.fields().to_owned()).to_equal([
    ("a", @value.Value(1)),
    ("a", @value.Value(2)),
  ])
}

///|
test "Value constructor normalizes integers and keeps scalar kinds" {
  @expect.expect_all(soft => {
    soft.expect(@value.Value(42)).to_equal(@value.Value::from_int(42L))
    soft.expect(@value.Value(42L)).to_equal(@value.Value::from_int(42L))
    soft.expect(@value.Value(42N)).to_equal(@value.Value::from_int(42L))
    soft
    .expect(@value.Value(9223372036854775808N))
    .to_equal(@value.Value::from_bigint(9223372036854775808N))
    soft.expect(@value.Value(true)).to_equal(@value.Value::from_bool(true))
    soft.expect(@value.Value(1.5)).to_equal(@value.Value::from_float(1.5))
    soft
    .expect(@value.Value("hello"))
    .to_equal(@value.Value::from_string("hello"))
  })
}

///|
test "converted domain values retain their kinds through the Ion codec" {
  let date : @value.Date = @value.Date(year=2024, month=2, day=29)
  let time : @value.Time = @value.Time(hour=12, minute=30, second=0)
  let timestamp : @value.Timestamp = @value.Timestamp(date, time)
  let months : @value.IntervalYM = @value.IntervalYM(-15)
  let duration : @value.IntervalDT = @value.IntervalDT(0, -250000000)
  let map = @value.MapValue(
    key_type=@value.MapType::String,
    value_type=@value.MapType::Dynamic,
    [(@value.Value("a"), @value.Value(1))],
  )
  let graph = @value.GraphValue([@value.GraphNode(id="n")], [])
  let values = [
    @value.Value(@ion_core.Decimal::parse("1.50")),
    @value.Value(date),
    @value.Value(time),
    @value.Value(timestamp),
    @value.Value(months),
    @value.Value(duration),
    @value.Value(map),
    @value.Value(graph),
  ]
  let binary = @partiql_ion.write_bytes(values)
  @expect.expect(@partiql_ion.read_bytes(binary)).to_equal(values)
}

///|
test "Value constructor converts nested lists and validated domain values" {
  let date : @value.Date = @value.Date(year=2024, month=2, day=29)
  let tuple : @value.Tuple = @value.Tuple([
    ("drop", @value.Value::Missing),
    ("date", @value.Value(date)),
  ])
  let bag : @value.Bag = @value.Bag([@value.Value(tuple), @value.Value(1)])
  @expect.expect_all(soft => {
    soft
    .expect(@value.Value([[1, 2], [3]]))
    .to_equal(
      @value.Value::from_list([
        @value.Value::from_list([
          @value.Value::from_int(1),
          @value.Value::from_int(2),
        ]),
        @value.Value::from_list([@value.Value::from_int(3)]),
      ]),
    )
    soft.expect(@value.Value(bag)).to_equal(@value.Value::from_bag(bag))
    soft
    .expect(@value.Value(tuple))
    .to_equal(
      @value.Value::from_tuple(
        @value.Tuple([("date", @value.Value::from_date(date))]),
      ),
    )
    soft
    .expect(@value.Value(@value.Value::Missing))
    .to_equal(@value.Value::Missing)
    soft
    .expect(@value.Value(@ion_core.IonValue::symbol("hello")))
    .to_equal(@value.Value::from_ion(@ion_core.IonValue::symbol("hello")))
  })
}

///|
test "typed scalar conversions preserve Ion kinds and normalize integers" {
  let values = [
    @value.Value::from_bool(true),
    @value.Value::from_int(9223372036854775807L),
    @value.Value::from_bigint(9223372036854775808N),
    @value.Value::from_bigint(1N),
    @value.Value::from_float(-0.0),
    @value.Value::from_decimal(@ion_core.Decimal::parse("1.50")),
    @value.Value::from_string("a"),
    @value.Value::from_clob(b"x"),
    @value.Value::from_blob(b"x"),
  ]
  @expect.expect(values).to_equal(
    @partiql_ion.read_text(
      "true 9223372036854775807 9223372036854775808 1 -0e0 1.50 \"a\" {{\"x\"}} {{eA==}}",
    ),
  )
}

///|
test "typed domain conversions resolve short constructors and retain kinds" {
  let date = @value.Value::from_date(@value.Date(year=2024, month=2, day=29))
  let time = @value.Value::from_time(@value.Time(hour=12, minute=30, second=0))
  let timestamp = @value.Value::from_timestamp(
    @value.Timestamp(
      @value.Date(year=2024, month=2, day=29),
      @value.Time(hour=12, minute=30, second=0),
    ),
  )
  let months = @value.Value::from_interval_ym(@value.IntervalYM(-15))
  let duration = @value.Value::from_interval_dt(
    @value.IntervalDT(0, -250000000),
  )
  let list = @value.Value::from_list([@value.Value(1)])
  let bag = @value.Value::from_bag(@value.Bag([@value.Value(1)]))
  let map = @value.Value::from_map(
    @value.MapValue(
      key_type=@value.MapType::String,
      value_type=@value.MapType::Dynamic,
      [(@value.Value("a"), @value.Value(1))],
    ),
  )
  let graph = @value.Value::from_graph(
    @value.GraphValue([@value.GraphNode(id="n")], []),
  )
  let ion = @value.Value::from_ion(@ion_core.IonValue::symbol("hello"))
  let values = [
    date, time, timestamp, months, duration, list, bag, map, graph, ion,
  ]
  @expect.expect_all(soft => {
    soft.expect(date is @value.Value::Date(d) && d.day == 29).to_be_true()
    soft.expect(time is @value.Value::Time(t) && t.minute == 30).to_be_true()
    soft.expect(timestamp is @value.Value::Timestamp(_)).to_be_true()
    soft
    .expect(months is @value.Value::IntervalYM(i) && i.months == -15)
    .to_be_true()
    soft
    .expect(duration is @value.Value::IntervalDT(i) && i.nanos == 750000000)
    .to_be_true()
    soft.expect(list is @value.Value::List(_)).to_be_true()
    soft.expect(bag is @value.Value::Bag(_)).to_be_true()
    soft.expect(map is @value.Value::Map(_)).to_be_true()
    soft.expect(graph is @value.Value::Graph(_)).to_be_true()
    soft.expect(ion is @value.Value::Ion(_)).to_be_true()
    soft
    .expect(@partiql_ion.read_bytes(@partiql_ion.write_bytes(values)))
    .to_equal(values)
  })
}

///|
test "typed list wrapping shares storage while generic array conversion copies" {
  let items = [@value.Value::from_int(1)]
  let wrapped = @value.Value::from_list(items)
  let converted = @value.Value(items)
  items[0] = @value.Value::from_int(2)
  guard wrapped is @value.Value::List(wrapped_items) else {
    fail("expected a wrapped list")
  }
  guard converted is @value.Value::List(converted_items) else {
    fail("expected a converted list")
  }
  @expect.expect_all(soft => {
    soft.expect(wrapped_items[0]).to_equal(@value.Value::from_int(2))
    soft.expect(converted_items[0]).to_equal(@value.Value::from_int(1))
  })
}
