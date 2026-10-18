///|
/// A timestamp at midnight UTC on 2020-01-01, as TIMESTAMP '2020-01-01 00:00:00'
/// compares.
let ion_midnight : String = "`2020-01-01T00:00:00Z`"

///|
test "Ion literals are values of the data model" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("`1`"))
    .to_equal(@value.Value::from_ion(@ion.IonValue::int(1)))
    soft.expect(ev("`1` + 1")).to_equal(@value.Value::from_int(2))
    soft.expect(ev("`\"a\"` || 'b'")).to_equal(@value.Value::from_string("ab"))
    soft.expect(ev("`a` = 'a'")).to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("`null.int` IS NULL"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("`[1, 2]`[1]"))
    .to_equal(@value.Value::from_ion(@ion.IonValue::int(2)))
    soft
    .expect(ev("`{a: 1}`.a"))
    .to_equal(@value.Value::from_ion(@ion.IonValue::int(1)))
    soft
    .expect(ev("`2.5e0` IS DOUBLE PRECISION"))
    .to_equal(@value.Value::from_bool(true))
  })
}

///|
test "an Ion datetime compares as the datetime it stands for" {
  let ts = "TIMESTAMP '2020-01-01 00:00:00'"
  @expect.expect_all(soft => {
    soft
    .expect(ev("\{ion_midnight} = \{ts}"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("\{ts} = \{ion_midnight}"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("\{ion_midnight} <> \{ts}"))
    .to_equal(@value.Value::from_bool(false))
    soft
    .expect(ev("\{ion_midnight} <= \{ts}"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("\{ion_midnight} = DATE '2020-01-01'"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("CASE \{ion_midnight} WHEN \{ts} THEN 1 ELSE 2 END"))
    .to_equal(@value.Value::from_int(1))
    soft.expect(ev("NULLIF(\{ion_midnight}, \{ts})")).to_equal(Null)
  })
}

///|
test "an Ion string is a struct key" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(ev("{`\"k\"`: 1}", mode~))
      .to_equal(
        @value.Value::from_tuple(
          @value.Tuple([("k", @value.Value::from_int(1))]),
        ),
      )
      soft
      .expect(ev("{`k`: 1}", mode~))
      .to_equal(
        @value.Value::from_tuple(
          @value.Tuple([("k", @value.Value::from_int(1))]),
        ),
      )
    }
    soft
    .expect(ev("{`1`: 1}"))
    .to_equal(@value.Value::from_tuple(@value.Tuple([])))
    soft
    .expect_call(() => ev("{`1`: 1}", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}

///|
test "Ion map keys are lowered before the key type is inferred" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("MAP {`1`: 'a', 2: 'b'}"))
    .to_equal(
      @value.Value::from_map(
        @value.MapValue(key_type=Integer, value_type=String, [
          (@value.Value::from_int(1), @value.Value::from_string("a")),
          (@value.Value::from_int(2), @value.Value::from_string("b")),
        ]),
      ),
    )
    soft
    .expect(ev("MAP {'a': `1`, 'b': 2}"))
    .to_equal(
      @value.Value::from_map(
        @value.MapValue(key_type=String, value_type=Integer, [
          (@value.Value::from_string("a"), @value.Value::from_int(1)),
          (@value.Value::from_string("b"), @value.Value::from_int(2)),
        ]),
      ),
    )
    soft
    .expect(ev("MAP {`1`: 'a', 1: 'b'}"))
    .to_equal(
      @value.Value::from_map(
        @value.MapValue(key_type=Integer, value_type=String, [
          (@value.Value::from_int(1), @value.Value::from_string("b")),
        ]),
      ),
    )
  })
}

///|
test "an Ion string subscript names a tuple field" {
  @expect.expect_all(soft => {
    soft.expect(ev("{'a': 1}[`\"a\"`]")).to_equal(@value.Value::from_int(1))
    soft.expect(ev("{'a': 1}[`a`]")).to_equal(@value.Value::from_int(1))
    soft.expect(ev("{'a': 1}['a']")).to_equal(@value.Value::from_int(1))
  })
}

///|
test "Bindings::of_ion reads a struct and rejects anything else" {
  let env = @eval.Bindings::of_ion(@text.read_ion("{a: 1, b: [2]}"))
  @expect.expect_all(soft => {
    soft
    .expect(@eval.evaluate_text("a + 1", env~))
    .to_equal(@value.Value::from_int(2))
    soft
    .expect(@eval.evaluate_text("b[0]", env~))
    .to_equal(@value.Value::from_int(2))
    for text in ["[1]", "1", "null"] {
      soft
      .expect_call(() => @eval.Bindings::of_ion(@text.read_ion(text)))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError for \{text}",
      )
    }
  })
}
