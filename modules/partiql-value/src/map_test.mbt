///|
fn map_of(
  pairs : Array[(@value.Value, @value.Value)],
  key_type? : @value.MapType = String,
  value_type? : @value.MapType = Dynamic,
) -> @value.MapValue raise {
  @value.MapValue::new(key_type~, value_type~, pairs)
}

///|
fn invalid_key(e : Error) -> Bool {
  e is @value.MapError::InvalidKey(_)
}

///|
test "map constructor keeps order, drops MISSING values, keeps NULL values" {
  let m = map_of([
    (s("b"), i(2)),
    (s("a"), @value.Value::Missing),
    (s("c"), @value.Value::Null),
  ])
  @expect.expect_all(soft => {
    soft.expect(m.length()).to_equal(2)
    soft
    .expect(m.entries().to_owned())
    .to_equal([(s("b"), i(2)), (s("c"), @value.Value::Null)])
  })
}

///|
test "map constructor rejects invalid keys" {
  @expect.expect_all(soft => {
    for
      key in [
        @value.Value::Null,
        @value.Value::Missing,
        @value.Value::List([i(1)]),
        tup([("a", i(1))]),
        bag([]),
      ] {
      soft
      .expect_call(() => map_of([(key, i(1))]), label=@debug.to_string(key))
      .to_raise_matching(invalid_key, description="InvalidKey")
    }
  })
}

///|
test "map constructor rejects keys that are eqg-equal" {
  let one_decimal = @value.Value::Decimal(@ion_core.Decimal::new(10N, -1))
  @expect.expect_all(soft => {
    soft
    .expect_call(() => {
      map_of([(i(1), s("x")), (one_decimal, s("y"))], key_type=Integer)
    })
    .to_raise_matching(
      e => e is @value.MapError::DuplicateKey(_),
      description="DuplicateKey",
    )
    soft
    .expect_call(() => map_of([(ion("hello"), i(1)), (s("hello"), i(2))]))
    .to_raise_matching(
      e => e is @value.MapError::DuplicateKey(_),
      description="DuplicateKey",
    )
    soft
    .expect_call(() => map_of([], key_type=Dynamic))
    .to_raise_matching(
      e => e is @value.MapError::DynamicKeyType,
      description="DynamicKeyType",
    )
  })
}

///|
test "map type names round trip" {
  let all : Array[@value.MapType] = [
    Dynamic,
    Bool,
    TinyInt,
    SmallInt,
    Integer,
    BigInt,
    Numeric,
    Decimal,
    Real,
    Double,
    String,
    Char,
    Varchar,
    Date,
    Time,
    Timestamp,
  ]
  @expect.expect_all(soft => {
    for t in all {
      soft
      .expect(@value.MapType::from_name(t.name()), label=t.name())
      .to_equal(Some(t))
    }
    soft.expect(@value.MapType::from_name("int")).to_equal(Some(Integer))
    soft.expect(@value.MapType::from_name("foo")).to_equal(None)
  })
}

///|
test "map identity sees type parameters and ignores entry order" {
  let a = map_of([(s("a"), i(1)), (s("b"), i(2))], value_type=Integer)
  let b = map_of([(s("b"), i(2)), (s("a"), i(1))], value_type=Integer)
  let c = map_of([(s("a"), i(1)), (s("b"), i(2))], value_type=BigInt)
  @expect.expect_all(soft => {
    soft.expect(@value.Value::Map(a) == @value.Value::Map(b)).to_be_true()
    soft.expect(@value.Value::Map(a) == @value.Value::Map(c)).to_be_false()
  })
}

///|
fn mv(
  pairs : Array[(@value.Value, @value.Value)],
  value_type? : @value.MapType = Integer,
) -> @value.Value raise {
  @value.Value::Map(map_of(pairs, value_type~))
}

///|
test "map equality follows RFC 0104" {
  @expect.expect_all(soft => {
    soft
    .expect(
      @value.sql_equals(
        mv([(s("a"), i(1)), (s("b"), i(2))]),
        mv([(s("b"), i(2)), (s("a"), i(1))]),
      ),
    )
    .to_equal(t)
    soft
    .expect(@value.sql_equals(mv([(s("a"), i(1))]), mv([(s("a"), i(2))])))
    .to_equal(f)
    soft
    .expect(
      @value.sql_equals(
        mv([(s("a"), i(1))]),
        mv([(s("a"), i(1)), (s("b"), i(2))]),
      ),
    )
    .to_equal(f)
    soft
    .expect(@value.sql_equals(mv([(s("a"), i(1))]), tup([("a", i(1))])))
    .to_equal(f)
    soft
    .expect(@value.eqg(mv([], value_type=Dynamic), mv([], value_type=Integer)))
    .to_be_true()
    soft
    .expect(
      @value.sql_equals(
        mv([(s("b"), @value.Value::Null)]),
        mv([(s("b"), @value.Value::Null)]),
      ),
    )
    .to_equal(t)
  })
}

///|
test "maps order by sorted entries, after bags" {
  let a1 = mv([(s("a"), i(1))])
  let a1b2 = mv([(s("b"), i(2)), (s("a"), i(1))])
  let b2 = mv([(s("b"), i(2))])
  @expect.expect_all(soft => {
    soft.expect(@value.compare(a1, a1b2, nulls=NullsFirst)).to_equal(-1)
    soft.expect(@value.compare(a1b2, b2, nulls=NullsFirst)).to_equal(-1)
    soft.expect(@value.compare(a1, b2, nulls=NullsFirst)).to_equal(-1)
    soft.expect(@value.compare(bag([i(9)]), a1, nulls=NullsFirst)).to_equal(-1)
    soft
    .expect(
      @value.compare(
        a1b2,
        mv([(s("a"), i(1)), (s("b"), i(2))]),
        nulls=NullsFirst,
      ),
    )
    .to_equal(0)
  })
}
