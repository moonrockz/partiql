///|
fn nested_list(leaf : @value.Value, depth : Int32) -> @value.Value {
  let mut value = leaf
  for _ in 0..<depth {
    value = @value.Value::from_list([value])
  }
  value
}

///|
test "grouping equality handles 100000 nested lists" {
  let a = nested_list(@value.Value::from_int(1), 100000)
  let b = nested_list(@value.Value::from_int(1), 100000)
  @expect.expect(@value.eqg(a, b)).to_be_true()
}

///|
test "ordering handles 100000 nested lists" {
  let a = nested_list(@value.Value::from_int(1), 100000)
  let b = nested_list(@value.Value::from_int(2), 100000)
  @expect.expect(@value.compare(a, b, nulls=NullsFirst)).to_equal(-1)
}

///|
test "debug formatting handles 100000 nested lists" {
  @expect.expect(
    @debug.to_string(nested_list(@value.Value::from_int(1), 100000)).contains(
      "...",
    ),
  ).to_be_true()
}

///|
test "deep lowering handles 100000 nested lists" {
  let a = nested_list(
    @value.Value::from_ion(@ion_core.IonValue::int(1)),
    100000,
  )
  @expect.expect(
    @value.eqg(a.lower_deep(), nested_list(@value.Value::from_int(1), 100000)),
  ).to_be_true()
}

///|
fn nested_containers(leaf : @value.Value, depth : Int32) -> @value.Value raise {
  let mut v = leaf
  for i in 0..<depth {
    v = match i % 6 {
      0 => @value.Value::from_list([v])
      1 => @value.Value::from_bag(@value.Bag([v]))
      2 => @value.Value::from_tuple(@value.Tuple([("a", v)]))
      3 =>
        @value.Value::from_map(
          @value.MapValue(key_type=String, value_type=Dynamic, [
            (@value.Value::from_string("k"), v),
          ]),
        )
      4 =>
        @value.Value::from_graph(
          @value.GraphValue([@value.GraphNode(id="n", payload=Some(v))], []),
        )
      _ =>
        @value.Value::from_graph(
          @value.GraphValue([@value.GraphNode(id="n")], [
            @value.GraphEdge(
              id="e",
              ends=Directed(from="n", to="n"),
              payload=Some(v),
            ),
          ]),
        )
    }
  }
  v
}

///|
test "all relations traverse 100000 mixed containers" {
  let a = nested_containers(@value.Value::from_int(1), 100000)
  let b = nested_containers(@value.Value::from_int(1), 100000)
  let c = nested_containers(@value.Value::from_int(2), 100000)
  @expect.expect_all(soft => {
    soft.expect(a == b).to_be_true()
    soft.expect(a == c).to_be_false()
    soft.expect(@value.eqg(a, b)).to_be_true()
    soft.expect(@value.eqg(a, c)).to_be_false()
    soft.expect(@value.sql_equals(a, b) is Bool(true)).to_be_true()
    soft.expect(@value.sql_equals(a, c) is Bool(false)).to_be_true()
    soft.expect(@value.compare(a, b, nulls=NullsFirst)).to_equal(0)
    soft.expect(@value.compare(a, c, nulls=NullsLast)).to_equal(-1)
    soft.expect(@value.compare(c, a, nulls=NullsFirst)).to_equal(1)
    soft.expect(@debug.to_string(a).contains("...")).to_be_true()
    soft.expect(a.lower_deep() == b).to_be_true()
  })
}

///|
test "map construction reports a deeply nested invalid key" {
  let key = nested_list(@value.Value::from_int(1), 100000)
  @expect.expect_call(() => {
    @value.MapValue(key_type=String, value_type=Dynamic, [
      (key, @value.Value::from_int(1)),
    ])
  }).to_raise_matching(
    e => e is @value.MapError::InvalidKey(_),
    description="InvalidKey",
  )
}

///|
test "boxed Ion identity, lowering and debug traverse 100000 containers" {
  let mut x = @ion_core.IonValue::int(1)
  let mut y = @ion_core.IonValue::int(2)
  for i in 0..<100000 {
    if i % 3 == 0 {
      x = @ion_core.IonValue::from_fields([@ion_core.Field::Field("a", x)])
      y = @ion_core.IonValue::from_fields([@ion_core.Field::Field("a", y)])
    } else if i % 3 == 1 {
      x = @ion_core.IonValue::list([x])
      y = @ion_core.IonValue::list([y])
    } else {
      x = @ion_core.IonValue::sexp([x])
      y = @ion_core.IonValue::sexp([y])
    }
  }
  let a = @value.Value::from_ion(x)
  let b = @value.Value::from_ion(y)
  @expect.expect_all(soft => {
    soft.expect(a == a).to_be_true()
    soft.expect(a == b).to_be_false()
    soft.expect(@value.eqg(a, a)).to_be_true()
    soft.expect(@value.compare(a, b, nulls=NullsFirst)).to_equal(-1)
    soft.expect(@value.eqg(a.lower_deep(), a)).to_be_true()
    soft.expect(@debug.to_string(a).contains("...")).to_be_true()
  })
}

///|
test "unordered matching and sorting compare deeply nested candidates" {
  let one = nested_list(@value.Value::from_int(1), 100000)
  let two = nested_list(@value.Value::from_int(2), 100000)
  let a = @value.Value::from_bag(@value.Bag([one, two]))
  let b = @value.Value::from_bag(@value.Bag([two, one]))
  let c = @value.Value::from_bag(@value.Bag([one, one]))
  let t = @value.Value::from_tuple(@value.Tuple([("a", one), ("a", two)]))
  let u = @value.Value::from_tuple(@value.Tuple([("a", two), ("a", one)]))
  @expect.expect_all(soft => {
    soft.expect(a == b).to_be_true()
    soft.expect(@value.eqg(a, b)).to_be_true()
    soft.expect(@value.eqg(a, c)).to_be_false()
    soft.expect(@value.compare(a, b, nulls=NullsFirst)).to_equal(0)
    soft.expect(@value.compare(c, b, nulls=NullsLast)).to_equal(-1)
    soft.expect(t == u).to_be_true()
    soft.expect(@value.compare(t, u, nulls=NullsFirst)).to_equal(0)
  })
}

///|
test "unlowerable Ion structs use stack-safe structural fallback" {
  let mut x = @ion_core.IonValue::int(1)
  for _ in 0..<100000 {
    x = @ion_core.IonValue::list([x])
  }
  let a = @value.Value::from_ion(
    @ion_core.IonValue::from_fields([
      @ion_core.Field::from_token(@ion_core.SymbolToken::from_sid(10), x),
    ]),
  )
  @expect.expect_all(soft => {
    soft.expect(@value.eqg(a, a)).to_be_true()
    soft.expect(@value.sql_equals(a, a) is Bool(true)).to_be_true()
    soft
    .expect_call(() => a.lower_deep())
    .to_raise_matching(
      e => e is @value.LowerError::SymbolWithoutText,
      description="SymbolWithoutText",
    )
  })
}
