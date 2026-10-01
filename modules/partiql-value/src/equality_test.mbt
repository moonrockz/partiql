///|
fn i(n : Int) -> @value.Value {
  @value.Value::Int(n.to_int64())
}

///|
fn s(text : String) -> @value.Value {
  @value.Value::String(text)
}

///|
fn bag(items : Array[@value.Value]) -> @value.Value {
  @value.Value::Bag(@value.Bag::new(items))
}

///|
fn tup(pairs : Array[(String, @value.Value)]) -> @value.Value {
  @value.Value::Tuple(@value.Tuple::new(pairs))
}

///|
fn ion(text : String) -> @value.Value raise {
  @value.Value::Ion(@text.read_ion(text))
}

///|
let t : @value.Value = @value.Value::Bool(true)

///|
let f : @value.Value = @value.Value::Bool(false)

///|
test "spec examples for =" {
  @expect.expect_all(soft => {
    soft.expect(@value.sql_equals(i(5), s("a"))).to_equal(f)
    soft
    .expect(
      @value.sql_equals(
        bag([i(3), i(2), i(4), i(2)]),
        bag([i(2), i(2), i(3), i(4)]),
      ),
    )
    .to_equal(t)
    soft
    .expect(
      @value.sql_equals(@value.Value::List([i(1), i(2)]), bag([i(1), i(2)])),
    )
    .to_equal(f)
    soft
    .expect(
      @value.sql_equals(
        tup([("a", i(1)), ("b", i(2))]),
        tup([("b", i(2)), ("a", i(1))]),
      ),
    )
    .to_equal(t)
    soft
    .expect(@value.sql_equals(@value.Value::Null, @value.Value::Missing))
    .to_equal(@value.Value::Missing)
    soft
    .expect(@value.sql_equals(@value.Value::Null, i(1)))
    .to_equal(@value.Value::Null)
    soft.expect(@value.sql_equals(ion("hello"), s("hello"))).to_equal(t)
    soft
    .expect(@value.sql_equals(ion("(1 2)"), @value.Value::List([i(1), i(2)])))
    .to_equal(t)
  })
}

///|
test "numbers compare across types" {
  @expect.expect_all(soft => {
    let one_dec = @value.Value::Decimal(@ion_core.Decimal::new(10N, -1))
    soft.expect(@value.sql_equals(i(1), one_dec)).to_equal(t)
    soft.expect(@value.sql_equals(i(1), @value.Value::Float(1.0))).to_equal(t)
    soft
    .expect(
      @value.sql_equals(@value.Value::Float(0.0), @value.Value::Float(-0.0)),
    )
    .to_equal(t)
    let nan = @value.Value::Float(@double.not_a_number)
    soft.expect(@value.sql_equals(nan, nan)).to_equal(f)
  })
}

///|
test "clob equals blob with the same octets" {
  @expect.expect(
    @value.sql_equals(@value.Value::Clob(b"x"), @value.Value::Blob(b"x")),
  ).to_equal(t)
}

///|
test "timestamps: instant equality only with a time zone" {
  @expect.expect_all(soft => {
    let date = @value.Date::new(year=2024, month=1, day=1)
    let a = @value.Value::Timestamp(
      @value.Timestamp::new(
        date,
        @value.Time::new(hour=1, minute=0, second=0, offset=Some(60)),
      ),
    )
    let b = @value.Value::Timestamp(
      @value.Timestamp::new(
        date,
        @value.Time::new(hour=0, minute=0, second=0, offset=Some(0)),
      ),
    )
    let c = @value.Value::Timestamp(
      @value.Timestamp::new(date, @value.Time::new(hour=0, minute=0, second=0)),
    )
    soft.expect(@value.sql_equals(a, b)).to_equal(t)
    soft.expect(@value.sql_equals(b, c)).to_equal(f)
  })
}

///|
test "nested absent values compare with eqg" {
  @expect.expect_all(soft => {
    soft
    .expect(
      @value.sql_equals(
        @value.Value::List([@value.Value::Null]),
        @value.Value::List([@value.Value::Null]),
      ),
    )
    .to_equal(t)
    soft
    .expect(
      @value.sql_equals(
        @value.Value::List([@value.Value::Null]),
        @value.Value::List([@value.Value::Missing]),
      ),
    )
    .to_equal(f)
  })
}

///|
test "eqg" {
  @expect.expect_all(soft => {
    soft.expect(@value.eqg(@value.Value::Null, @value.Value::Null)).to_be_true()
    soft
    .expect(@value.eqg(@value.Value::Missing, @value.Value::Missing))
    .to_be_true()
    soft
    .expect(@value.eqg(@value.Value::Null, @value.Value::Missing))
    .to_be_false()
    let nan = @value.Value::Float(@double.not_a_number)
    soft.expect(@value.eqg(nan, nan)).to_be_true()
    soft.expect(@value.eqg(i(2), @value.Value::Float(2.0))).to_be_true()
  })
}
