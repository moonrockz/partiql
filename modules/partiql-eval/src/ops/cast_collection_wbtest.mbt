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
    @value.Value::Map(@value.MapValue::new(key_type~, value_type~, entries))
  catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
test "cast to LIST, BAG and TUPLE" {
  let items : Array[@value.Value] = [Int(1), Int(2)]
  @expect.expect_all(soft => {
    soft.expect(cast(List(items), List)).to_equal(List(items))
    soft.expect(cast(List(items), Bag)).to_equal(Bag(@value.Bag::new(items)))
    soft.expect(cast(Bag(@value.Bag::new(items)), List)).to_equal(List(items))
    soft
    .expect(cast(tup([("a", Int(1))]), Tuple))
    .to_equal(tup([("a", Int(1))]))
    soft.expect(failure(() => cast(Int(1), List))).to_equal("type")
    soft.expect(failure(() => cast(List(items), Tuple))).to_equal("type")
    let sexp = @value.Value::Ion(@ion_core.IonValue::sexp([]))
    soft.expect(cast(sexp, List)).to_equal(List([]))
  })
}

///|
test "cast to MAP" {
  let string_int = map_target(Text(String), String, Integer(Bits32), Integer)
  @expect.expect_all(soft => {
    soft
    .expect(cast(tup([("a", Int(1)), ("b", Int(2))]), string_int))
    .to_equal(
      map_value(String, Integer, [(String("a"), Int(1)), (String("b"), Int(2))]),
    )
    soft
    .expect(cast(tup([]), string_int))
    .to_equal(map_value(String, Integer, []))
    soft
    .expect(cast(tup([("a", Int(1)), ("a", Int(2))]), string_int))
    .to_equal(map_value(String, Integer, [(String("a"), Int(2))]))
    soft
    .expect(cast(tup([("a", Int(1)), ("b", Missing)]), string_int))
    .to_equal(map_value(String, Integer, [(String("a"), Int(1))]))
    soft
    .expect(cast(tup([("a", String("12"))]), string_int))
    .to_equal(map_value(String, Integer, [(String("a"), Int(12))]))
    soft
    .expect(failure(() => cast(tup([("a", String("x"))]), string_int)))
    .to_equal("type")
    let int_int = map_target(Integer(Bits32), Integer, Integer(Bits32), Integer)
    soft
    .expect(failure(() => cast(tup([("1", Int(1))]), int_int)))
    .to_equal("type")
    let source = map_value(Integer, String, [
      (Int(1), String("one")),
      (Int(2), String("two")),
    ])
    let string_string = map_target(Text(String), String, Text(String), String)
    soft
    .expect(cast(source, string_string))
    .to_equal(
      map_value(String, String, [
        (String("1"), String("one")),
        (String("2"), String("two")),
      ]),
    )
    let tiny = map_target(Text(String), String, Integer(Bits8), TinyInt)
    soft
    .expect(
      failure(() => {
        cast(map_value(String, Integer, [(String("a"), Int(300))]), tiny)
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
    .expect(cast(tup([("ab", Int(1)), ("ac", Int(2))]), short_keys))
    .to_equal(map_value(Varchar, Integer, [(String("a"), Int(2))]))
    soft.expect(failure(() => cast(source, Tuple))).to_equal("type")
    soft.expect(failure(() => cast(List([]), string_int))).to_equal("type")
  })
}
