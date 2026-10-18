///|
test "Value constructor normalizes integers and keeps scalar kinds" {
  @expect.expect_all(soft => {
    soft.expect(@value.Value(42)).to_equal(@value.Value::Int(42L))
    soft.expect(@value.Value(42L)).to_equal(@value.Value::Int(42L))
    soft.expect(@value.Value(42N)).to_equal(@value.Value::Int(42L))
    soft
    .expect(@value.Value(9223372036854775808N))
    .to_equal(@value.Value::BigInt(9223372036854775808N))
    soft.expect(@value.Value(true)).to_equal(@value.Value::Bool(true))
    soft.expect(@value.Value(1.5)).to_equal(@value.Value::Float(1.5))
    soft.expect(@value.Value("hello")).to_equal(@value.Value::String("hello"))
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
    .to_equal(@value.Value::List([List([Int(1), Int(2)]), List([Int(3)])]))
    soft.expect(@value.Value(bag)).to_equal(@value.Value::Bag(bag))
    soft
    .expect(@value.Value(tuple))
    .to_equal(
      @value.Value::Tuple(@value.Tuple([("date", @value.Value::Date(date))])),
    )
    soft
    .expect(@value.Value(@value.Value::Missing))
    .to_equal(@value.Value::Missing)
    soft
    .expect(@value.Value(@ion_core.IonValue::symbol("hello")))
    .to_equal(@value.Value::Ion(@ion_core.IonValue::symbol("hello")))
  })
}
