///|
fn tup(fields : Array[(String, @value.Value)]) -> @value.Value {
  Tuple(@value.Tuple::new(fields))
}

///|
test "SIZE, CARDINALITY and EXISTS count every element" {
  let list = @value.Value::List([Null, Missing, Int(1)])
  let bag = @value.Value::Bag(@value.Bag::new([]))
  let fields = tup([("a", Int(1)), ("a", Int(2))])
  @expect.expect_all(soft => {
    soft.expect(size([list])).to_equal(Int(3))
    soft.expect(cardinality([bag])).to_equal(Int(0))
    soft.expect(size([fields])).to_equal(Int(2))
    soft.expect(exists([list])).to_equal(Bool(true))
    soft.expect(exists([bag])).to_equal(Bool(false))
    soft.expect(exists([tup([("a", Null)])])).to_equal(Bool(true))
    soft.expect(size([Null])).to_equal(Null)
    soft.expect(cardinality([Missing])).to_equal(Missing)
    soft.expect(failure(() => cardinality([String("foo")]))).to_equal("type")
    soft.expect(failure(() => exists([Int(1)]))).to_equal("type")
  })
}

///|
test "TUPLEUNION keeps every field in order" {
  @expect.expect_all(soft => {
    soft
    .expect(
      tuple_union([tup([("b", Int(2))]), tup([("a", Int(1)), ("b", Int(3))])]),
    )
    .to_equal(tup([("b", Int(2)), ("a", Int(1)), ("b", Int(3))]))
    soft.expect(tuple_union([])).to_equal(tup([]))
    soft.expect(tuple_union([tup([]), Null])).to_equal(Null)
    soft.expect(tuple_union([Null, Missing])).to_equal(Missing)
    soft.expect(failure(() => tuple_union([tup([]), Int(1)]))).to_equal("type")
  })
}
