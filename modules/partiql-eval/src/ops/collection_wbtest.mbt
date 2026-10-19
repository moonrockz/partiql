///|
fn tup(fields : Array[(String, @value.Value)]) -> @value.Value {
  @value.Value::from_tuple(@value.Tuple(fields))
}

///|
test "SIZE, CARDINALITY and EXISTS count every element" {
  let list = @value.Value::from_list([Null, Missing, @value.Value::from_int(1)])
  let bag = @value.Value::from_bag(@value.Bag([]))
  let fields = tup([
    ("a", @value.Value::from_int(1)),
    ("a", @value.Value::from_int(2)),
  ])
  @expect.expect_all(soft => {
    soft.expect(size([list])).to_equal(@value.Value::from_int(3))
    soft.expect(cardinality([bag])).to_equal(@value.Value::from_int(0))
    soft.expect(size([fields])).to_equal(@value.Value::from_int(2))
    soft.expect(exists([list])).to_equal(@value.Value::from_bool(true))
    soft.expect(exists([bag])).to_equal(@value.Value::from_bool(false))
    soft
    .expect(exists([tup([("a", Null)])]))
    .to_equal(@value.Value::from_bool(true))
    soft.expect(size([Null])).to_equal(Null)
    soft.expect(cardinality([Missing])).to_equal(Missing)
    soft
    .expect(failure(() => cardinality([@value.Value::from_string("foo")])))
    .to_equal("type")
    soft
    .expect(failure(() => exists([@value.Value::from_int(1)])))
    .to_equal("type")
  })
}

///|
test "TUPLEUNION keeps every field in order" {
  @expect.expect_all(soft => {
    soft
    .expect(
      tuple_union([
        tup([("b", @value.Value::from_int(2))]),
        tup([("a", @value.Value::from_int(1)), ("b", @value.Value::from_int(3))]),
      ]),
    )
    .to_equal(
      tup([
        ("b", @value.Value::from_int(2)),
        ("a", @value.Value::from_int(1)),
        ("b", @value.Value::from_int(3)),
      ]),
    )
    soft.expect(tuple_union([])).to_equal(tup([]))
    soft.expect(tuple_union([tup([]), Null])).to_equal(Null)
    soft.expect(tuple_union([Null, Missing])).to_equal(Missing)
    soft
    .expect(failure(() => tuple_union([tup([]), @value.Value::from_int(1)])))
    .to_equal("type")
  })
}

///|
fn map_of(
  key_type : @value.MapType,
  entries : Array[(@value.Value, @value.Value)],
) -> @value.Value raise {
  @value.Value::from_map(
    @value.MapValue(key_type~, value_type=Dynamic, entries),
  )
}

///|
test "map key lookup is by value within a type family" {
  let decimals = map_of(Decimal, [
    (
      @value.Value::from_decimal(@ion_core.Decimal::parse("1.0")),
      @value.Value::from_string("one"),
    ),
  ])
  let ints = map_of(Integer, [
    (@value.Value::from_int(1), @value.Value::from_string("one")),
    (@value.Value::from_int(2), @value.Value::from_string("two")),
  ])
  @expect.expect_all(soft => {
    soft
    .expect(map_get([decimals, @value.Value::from_int(1)]))
    .to_equal(@value.Value::from_string("one"))
    soft
    .expect(map_get([ints, @value.Value::from_int(2)]))
    .to_equal(@value.Value::from_string("two"))
    soft
    .expect(failure(() => map_get([ints, @value.Value::from_int(9)])))
    .to_equal("type")
    soft
    .expect(failure(() => map_get([ints, @value.Value::from_string("1")])))
    .to_equal("type")
    soft.expect(map_get([ints, Null])).to_equal(Null)
    soft.expect(map_get([Null, @value.Value::from_int(1)])).to_equal(Null)
    soft.expect(map_get([ints, Missing])).to_equal(Missing)
    soft
    .expect(map_contains_key([ints, @value.Value::from_int(1)]))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(map_contains_key([ints, @value.Value::from_int(9)]))
    .to_equal(@value.Value::from_bool(false))
    soft
    .expect(map_contains_key([decimals, @value.Value::from_int(1)]))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(
      failure(() => map_contains_key([ints, @value.Value::from_string("1")])),
    )
    .to_equal("type")
    soft
    .expect(
      failure(() => {
        map_get([
          tup([("a", @value.Value::from_int(1))]),
          @value.Value::from_string("a"),
        ])
      }),
    )
    .to_equal("type")
  })
}

///|
test "MAP_KEYS, MAP_VALUES and MAP_ENTRIES give bags in insertion order" {
  let m = map_of(String, [
    (@value.Value::from_string("x"), @value.Value::from_int(1)),
    (@value.Value::from_string("y"), @value.Value::from_int(2)),
  ])
  let empty = map_of(String, [])
  @expect.expect_all(soft => {
    soft
    .expect(map_keys([m]))
    .to_equal(
      @value.Value::from_bag(
        @value.Bag([
          @value.Value::from_string("x"),
          @value.Value::from_string("y"),
        ]),
      ),
    )
    soft
    .expect(map_values([m]))
    .to_equal(
      @value.Value::from_bag(
        @value.Bag([@value.Value::from_int(1), @value.Value::from_int(2)]),
      ),
    )
    soft
    .expect(map_entries([m]))
    .to_equal(
      @value.Value::from_bag(
        @value.Bag([
          tup([
            ("k", @value.Value::from_string("x")),
            ("v", @value.Value::from_int(1)),
          ]),
          tup([
            ("k", @value.Value::from_string("y")),
            ("v", @value.Value::from_int(2)),
          ]),
        ]),
      ),
    )
    soft
    .expect(map_keys([empty]))
    .to_equal(@value.Value::from_bag(@value.Bag([])))
    soft.expect(map_values([Null])).to_equal(Null)
  })
}
