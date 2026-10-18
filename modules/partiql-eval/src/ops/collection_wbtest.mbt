///|
fn tup(fields : Array[(String, @value.Value)]) -> @value.Value {
  @value.Value::from_tuple(@value.Tuple(fields))
}

///|
test "SIZE, CARDINALITY and EXISTS count every element" {
  let list = @value.Value::List([Null, Missing, Int(1)])
  let bag = @value.Value::Bag(@value.Bag::Bag([]))
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

///|
fn map_of(
  key_type : @value.MapType,
  entries : Array[(@value.Value, @value.Value)],
) -> @value.Value raise {
  Map(@value.MapValue(key_type~, value_type=Dynamic, entries))
}

///|
test "map key lookup is by value within a type family" {
  let decimals = map_of(Decimal, [
    (Decimal(@ion_core.Decimal::parse("1.0")), String("one")),
  ])
  let ints = map_of(Integer, [(Int(1), String("one")), (Int(2), String("two"))])
  @expect.expect_all(soft => {
    soft.expect(map_get([decimals, Int(1)])).to_equal(String("one"))
    soft.expect(map_get([ints, Int(2)])).to_equal(String("two"))
    soft.expect(failure(() => map_get([ints, Int(9)]))).to_equal("type")
    soft.expect(failure(() => map_get([ints, String("1")]))).to_equal("type")
    soft.expect(map_get([ints, Null])).to_equal(Null)
    soft.expect(map_get([Null, Int(1)])).to_equal(Null)
    soft.expect(map_get([ints, Missing])).to_equal(Missing)
    soft.expect(map_contains_key([ints, Int(1)])).to_equal(Bool(true))
    soft.expect(map_contains_key([ints, Int(9)])).to_equal(Bool(false))
    soft.expect(map_contains_key([decimals, Int(1)])).to_equal(Bool(true))
    soft
    .expect(failure(() => map_contains_key([ints, String("1")])))
    .to_equal("type")
    soft
    .expect(failure(() => map_get([tup([("a", Int(1))]), String("a")])))
    .to_equal("type")
  })
}

///|
test "MAP_KEYS, MAP_VALUES and MAP_ENTRIES give bags in insertion order" {
  let m = map_of(String, [(String("x"), Int(1)), (String("y"), Int(2))])
  let empty = map_of(String, [])
  @expect.expect_all(soft => {
    soft
    .expect(map_keys([m]))
    .to_equal(Bag(@value.Bag::Bag([String("x"), String("y")])))
    soft
    .expect(map_values([m]))
    .to_equal(Bag(@value.Bag::Bag([Int(1), Int(2)])))
    soft
    .expect(map_entries([m]))
    .to_equal(
      Bag(
        @value.Bag::Bag([
          tup([("k", String("x")), ("v", Int(1))]),
          tup([("k", String("y")), ("v", Int(2))]),
        ]),
      ),
    )
    soft.expect(map_keys([empty])).to_equal(Bag(@value.Bag::Bag([])))
    soft.expect(map_values([Null])).to_equal(Null)
  })
}
