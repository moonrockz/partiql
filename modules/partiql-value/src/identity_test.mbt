///|
fn int(n : Int) -> @value.Value {
  @value.Value::Int(n.to_int64())
}

///|
test "structural identity is type-strict" {
  @expect.expect_all(soft => {
    let one_decimal = @value.Value::Decimal(@ion_core.Decimal::new(1N, 0))
    soft.expect(int(1) == one_decimal).to_be_false()
    soft.expect(int(1) == int(1)).to_be_true()
  })
}

///|
test "decimal identity keeps scale" {
  let a = @value.Value::Decimal(@ion_core.Decimal::new(10N, -1))
  let b = @value.Value::Decimal(@ion_core.Decimal::new(1N, 0))
  @expect.expect(a == b).to_be_false()
}

///|
test "float identity: NaN equals NaN, zero signs differ" {
  @expect.expect_all(soft => {
    soft
    .expect(
      @value.Value::Float(@double.not_a_number) ==
      @value.Value::Float(@double.not_a_number),
    )
    .to_be_true()
    soft
    .expect(@value.Value::Float(0.0) == @value.Value::Float(-0.0))
    .to_be_false()
  })
}

///|
test "bags and tuples are multisets" {
  @expect.expect_all(soft => {
    let a = @value.Value::Bag(@value.Bag::new([int(1), int(2), int(2)]))
    let b = @value.Value::Bag(@value.Bag::new([int(2), int(1), int(2)]))
    let c = @value.Value::Bag(@value.Bag::new([int(1), int(1), int(2)]))
    soft.expect(a == b).to_be_true()
    soft.expect(a == c).to_be_false()
    let t1 = @value.Tuple::new([("a", int(1)), ("b", int(2)), ("a", int(3))])
    let t2 = @value.Tuple::new([("a", int(3)), ("a", int(1)), ("b", int(2))])
    soft.expect(@value.Value::Tuple(t1) == @value.Value::Tuple(t2)).to_be_true()
  })
}

///|
test "tuple constructor drops MISSING" {
  @expect.expect_all(soft => {
    let t = @value.Tuple::new([
      ("a", @value.Value::Missing),
      ("b", @value.Value::Null),
    ])
    soft.expect(t.length()).to_equal(1)
    soft.expect(t.get_all("b").length()).to_equal(1)
    soft.expect(t.get_all("B").length()).to_equal(0)
  })
}

///|
test "integer constructor normalizes" {
  @expect.expect_all(soft => {
    soft.expect(@value.Value::integer(5N) == int(5)).to_be_true()
    let big = 9223372036854775808N
    match @value.Value::integer(big) {
      BigInt(b) => soft.expect(b == big).to_be_true()
      other => fail("expected BigInt, got \{@debug.to_string(other)}")
    }
  })
}
