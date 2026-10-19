///|
test "JSON bindings support SELECT over exact JSON data" {
  let source = "{\"t\":[{\"a\":2},{\"a\":3}],\"n\":9223372036854775808}"
  let env = @eval.Bindings::from_json_text(source)
  let bytes_env = @eval.Bindings::from_json_bytes(@utf8.encode(source))
  @expect.expect_all(soft => {
    soft
    .expect(@eval.evaluate_text("SELECT VALUE r.a + 1 FROM t AS r", env~))
    .to_equal(@partiql_ion.read_text("$bag::[3,4]")[0])
    soft
    .expect(@eval.evaluate_text("n", env~))
    .to_equal(@eval.evaluate_text("n", env=bytes_env))
    soft
    .expect_call(() => @eval.Bindings::from_json_text("[]"))
    .to_raise_matching(
      e => e is @partiql_json.JsonError::Bindings(_),
      description="object environment",
    )
  })
}
