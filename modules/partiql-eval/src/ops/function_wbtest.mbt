///|
fn echo(xs : Array[@value.Value]) -> @value.Value {
  ignore(xs)
  String("computed")
}

///|
test "apply: a wrong type beats MISSING beats NULL" {
  @expect.expect_all(soft => {
    // A wrong type fails even when another argument is MISSING or NULL.
    soft
    .expect(
      failure(() => apply("F", [Text, Text], [Missing, Int(1)], xs => echo(xs))),
    )
    .to_equal("type")
    soft
    .expect(
      failure(() => apply("F", [Text, Text], [Null, Int(1)], xs => echo(xs))),
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
    .expect(apply("F", [Text, Text], [String("a"), Null], xs => echo(xs)))
    .to_equal(Null)
    soft
    .expect(
      apply("F", [Text, Text], [String("a"), String("b")], xs => echo(xs)),
    )
    .to_equal(String("computed"))
  })
}

///|
test "apply: Ion values are unboxed first" {
  let symbol = @value.Value::Ion(@ion_core.IonValue::symbol("abc"))
  @expect.expect(apply("F", [Text], [symbol], xs => xs[0])).to_equal(
    String("abc"),
  )
}

///|
test "Param::accepts" {
  @expect.expect_all(soft => {
    soft.expect(Param::Text.accepts(String("a"))).to_be_true()
    soft.expect(Param::Text.accepts(Clob(b"a"))).to_be_false()
    soft.expect(Param::Text.accepts(Int(1))).to_be_false()
    soft.expect(Param::Bytes.accepts(String("a"))).to_be_true()
    soft.expect(Param::Bytes.accepts(Blob(b"a"))).to_be_true()
    soft.expect(Param::Bytes.accepts(Clob(b"a"))).to_be_true()
    soft.expect(Param::Bytes.accepts(Bool(true))).to_be_false()
  })
}
