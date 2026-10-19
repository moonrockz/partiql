///|
test "Ion text and binary bindings evaluate identically" {
  let source = "{a: 2, b: $bag::[1, 3]}"
  let bytes = @partiql_ion.write_bytes(@partiql_ion.read_text(source))
  let text_env = @eval.Bindings::from_ion_text(source)
  let binary_env = @eval.Bindings::from_ion_bytes(bytes)
  @expect.expect_all(soft => {
    soft
    .expect(@eval.evaluate_text("a + 1", env=text_env))
    .to_equal(@value.Value::from_int(3))
    soft
    .expect(@eval.evaluate_text("b", env=text_env))
    .to_equal(@eval.evaluate_text("b", env=binary_env))
    for
      (text, expected) in [
        ("", @value.Value::from_bag(@value.Bag([]))),
        ("1", @value.Value::from_int(1)),
        (
          "1 $missing::null",
          @value.Value::from_bag(
            @value.Bag([@value.Value::from_int(1), Missing]),
          ),
        ),
      ] {
      let env = @eval.Bindings::empty().with_data(
        "t",
        @partiql_ion.read_text(text),
      )
      soft.expect(@eval.evaluate_text("t", env~)).to_equal(expected)
    }
    soft
    .expect_call(() => @eval.Bindings::from_ion_text("{} {}"))
    .to_raise_matching(
      e => e is @partiql_ion.IonDataError::Bindings(_),
      description="one environment struct",
    )
  })
}
