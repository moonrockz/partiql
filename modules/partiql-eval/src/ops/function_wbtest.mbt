///|
fn echo(xs : Array[@value.Value]) -> @value.Value {
  ignore(xs)
  @value.Value::from_string("computed")
}

///|
test "apply: a wrong type beats MISSING beats NULL" {
  @expect.expect_all(soft => {
    // A wrong type fails even when another argument is MISSING or NULL.
    soft
    .expect(
      failure(() => {
        apply("F", [Text, Text], [Missing, @value.Value::from_int(1)], xs => {
          echo(xs)
        })
      }),
    )
    .to_equal("type")
    soft
    .expect(
      failure(() => {
        apply("F", [Text, Text], [Null, @value.Value::from_int(1)], xs => {
          echo(xs)
        })
      }),
    )
    .to_equal("type")
    // MISSING beats NULL, in either position.
    soft
    .expect(apply("F", [Text, Text], [Null, Missing], xs => echo(xs)))
    .to_equal(Missing)
    soft
    .expect(apply("F", [Text, Text], [Missing, Null], xs => echo(xs)))
    .to_equal(Missing)
    soft
    .expect(
      apply("F", [Text, Text], [@value.Value::from_string("a"), Null], xs => {
        echo(xs)
      }),
    )
    .to_equal(Null)
    soft
    .expect(
      apply(
        "F",
        [Text, Text],
        [@value.Value::from_string("a"), @value.Value::from_string("b")],
        xs => echo(xs),
      ),
    )
    .to_equal(@value.Value::from_string("computed"))
  })
}

///|
test "apply: Ion values are unboxed first" {
  let symbol = @value.Value::from_ion(@ion_core.IonValue::symbol("abc"))
  @expect.expect(apply("F", [Text], [symbol], xs => xs[0])).to_equal(
    @value.Value::from_string("abc"),
  )
}

///|
test "Param::accepts" {
  @expect.expect_all(soft => {
    soft
    .expect(Param::Text.accepts(@value.Value::from_string("a")))
    .to_be_true()
    soft
    .expect(Param::Text.accepts(@value.Value::from_clob(b"a")))
    .to_be_false()
    soft.expect(Param::Text.accepts(@value.Value::from_int(1))).to_be_false()
    soft
    .expect(Param::Bytes.accepts(@value.Value::from_string("a")))
    .to_be_true()
    soft
    .expect(Param::Bytes.accepts(@value.Value::from_blob(b"a")))
    .to_be_true()
    soft
    .expect(Param::Bytes.accepts(@value.Value::from_clob(b"a")))
    .to_be_true()
    soft
    .expect(Param::Bytes.accepts(@value.Value::from_bool(true)))
    .to_be_false()
  })
}
