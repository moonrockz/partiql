///|
fn boxed(text : String) -> @value.Value raise {
  @value.Value::Ion(@text.read_ion(text))
}

///|
test "scalars lower to core values" {
  @expect.expect_all(soft => {
    soft.expect(boxed("hello").lower()).to_equal(@value.Value::String("hello"))
    soft
    .expect(boxed("\"hello\"").lower())
    .to_equal(@value.Value::String("hello"))
    soft.expect(boxed("null.int").lower()).to_equal(@value.Value::Null)
    soft.expect(boxed("a::b::5").lower()).to_equal(@value.Value::Int(5L))
    soft.expect(boxed("{{\"x\"}}").lower()).to_equal(@value.Value::Clob(b"x"))
  })
}

///|
test "containers lower one level and keep children boxed" {
  match boxed("(1 b)").lower() {
    List([Ion(_), Ion(_)]) => ()
    other => fail("unexpected \{@debug.to_string(other)}")
  }
  @expect.expect(boxed("(1 b)").lower_deep()).to_equal(
    @value.Value::List([@value.Value::Int(1L), @value.Value::String("b")]),
  )
}

///|
test "ion timestamps lower to timestamps with time zone" {
  @expect.expect_all(soft => {
    match boxed("2017-01-01T").lower() {
      Timestamp(t) => {
        soft
        .expect((t.date.year, t.date.month, t.date.day))
        .to_equal((2017, 1, 1))
        soft.expect(t.time.offset).to_equal(Some(0))
      }
      other => fail("unexpected \{@debug.to_string(other)}")
    }
    match boxed("2017-01-01T12:30:15.123-08:00").lower() {
      Timestamp(t) => {
        soft
        .expect((t.time.hour, t.time.minute, t.time.second))
        .to_equal((12, 30, 15))
        soft.expect((t.time.nanos, t.time.precision)).to_equal((123000000, 3))
        soft.expect(t.time.offset).to_equal(Some(-480))
      }
      other => fail("unexpected \{@debug.to_string(other)}")
    }
  })
}

///|
test "non-ion values are unchanged" {
  @expect.expect(@value.Value::Int(3L).lower()).to_equal(@value.Value::Int(3L))
}

///|
test "ion timestamps with huge fraction exponents lower quickly" {
  @expect.expect_all(soft => {
    for exponent in [-50000000, -2147483648] {
      let ts = @ion_core.Timestamp::new(
        year=2000,
        month=Some(1),
        day=Some(1),
        hour=Some(0),
        minute=Some(0),
        second=Some(0),
        fraction=Some(@ion_core.Decimal::new(1N, exponent)),
        offset=Some(Known(0)),
      )
      let t = @value.timestamp_of_ion(ts)
      soft
      .expect((t.time.nanos, t.time.precision), label="\{exponent}")
      .to_equal((0, 9))
    }
  })
}
