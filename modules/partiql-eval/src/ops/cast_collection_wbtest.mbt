///|
fn map_target(
  key : CastTarget,
  key_type : @value.MapType,
  value : CastTarget,
  value_type : @value.MapType,
) -> CastTarget {
  Map(key~, key_type~, value~, value_type~)
}

///|
fn map_value(
  key_type : @value.MapType,
  value_type : @value.MapType,
  entries : Array[(@value.Value, @value.Value)],
) -> @value.Value {
  try
    @value.Value::from_map(@value.MapValue(key_type~, value_type~, entries))
  catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
test "cast to LIST, BAG and TUPLE" {
  let items : Array[@value.Value] = [
    @value.Value::from_int(1),
    @value.Value::from_int(2),
  ]
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_list(items), List))
    .to_equal(@value.Value::from_list(items))
    soft
    .expect(cast(@value.Value::from_list(items), Bag))
    .to_equal(@value.Value::from_bag(@value.Bag(items)))
    soft
    .expect(cast(@value.Value::from_bag(@value.Bag(items)), List))
    .to_equal(@value.Value::from_list(items))
    soft
    .expect(cast(tup([("a", @value.Value::from_int(1))]), Tuple))
    .to_equal(tup([("a", @value.Value::from_int(1))]))
    soft
    .expect(failure(() => cast(@value.Value::from_int(1), List)))
    .to_equal("type")
    soft
    .expect(failure(() => cast(@value.Value::from_list(items), Tuple)))
    .to_equal("type")
    let sexp = @value.Value::from_ion(@ion_core.IonValue::sexp([]))
    soft.expect(cast(sexp, List)).to_equal(@value.Value::from_list([]))
  })
}

///|
test "cast to MAP" {
  let string_int = map_target(Text(String), String, Integer(Bits32), Integer)
  @expect.expect_all(soft => {
    soft
    .expect(
      cast(
        tup([("a", @value.Value::from_int(1)), ("b", @value.Value::from_int(2))]),
        string_int,
      ),
    )
    .to_equal(
      map_value(String, Integer, [
        (@value.Value::from_string("a"), @value.Value::from_int(1)),
        (@value.Value::from_string("b"), @value.Value::from_int(2)),
      ]),
    )
    soft
    .expect(cast(tup([]), string_int))
    .to_equal(map_value(String, Integer, []))
    soft
    .expect(
      cast(
        tup([("a", @value.Value::from_int(1)), ("a", @value.Value::from_int(2))]),
        string_int,
      ),
    )
    .to_equal(
      map_value(String, Integer, [
        (@value.Value::from_string("a"), @value.Value::from_int(2)),
      ]),
    )
    soft
    .expect(
      cast(tup([("a", @value.Value::from_int(1)), ("b", Missing)]), string_int),
    )
    .to_equal(
      map_value(String, Integer, [
        (@value.Value::from_string("a"), @value.Value::from_int(1)),
      ]),
    )
    soft
    .expect(cast(tup([("a", @value.Value::from_string("12"))]), string_int))
    .to_equal(
      map_value(String, Integer, [
        (@value.Value::from_string("a"), @value.Value::from_int(12)),
      ]),
    )
    soft
    .expect(
      failure(() => {
        cast(tup([("a", @value.Value::from_string("x"))]), string_int)
      }),
    )
    .to_equal("type")
    let int_int = map_target(Integer(Bits32), Integer, Integer(Bits32), Integer)
    soft
    .expect(
      failure(() => cast(tup([("1", @value.Value::from_int(1))]), int_int)),
    )
    .to_equal("type")
    let source = map_value(Integer, String, [
      (@value.Value::from_int(1), @value.Value::from_string("one")),
      (@value.Value::from_int(2), @value.Value::from_string("two")),
    ])
    let string_string = map_target(Text(String), String, Text(String), String)
    soft
    .expect(cast(source, string_string))
    .to_equal(
      map_value(String, String, [
        (@value.Value::from_string("1"), @value.Value::from_string("one")),
        (@value.Value::from_string("2"), @value.Value::from_string("two")),
      ]),
    )
    let tiny = map_target(Text(String), String, Integer(Bits8), TinyInt)
    soft
    .expect(
      failure(() => {
        cast(
          map_value(String, Integer, [
            (@value.Value::from_string("a"), @value.Value::from_int(300)),
          ]),
          tiny,
        )
      }),
    )
    .to_equal("data")
    let short_keys = map_target(
      Text(Varchar(1)),
      Varchar,
      Integer(Bits32),
      Integer,
    )
    soft
    .expect(
      cast(
        tup([
          ("ab", @value.Value::from_int(1)),
          ("ac", @value.Value::from_int(2)),
        ]),
        short_keys,
      ),
    )
    .to_equal(
      map_value(Varchar, Integer, [
        (@value.Value::from_string("a"), @value.Value::from_int(2)),
      ]),
    )
    soft.expect(failure(() => cast(source, Tuple))).to_equal("type")
    soft
    .expect(failure(() => cast(@value.Value::from_list([]), string_int)))
    .to_equal("type")
  })
}
