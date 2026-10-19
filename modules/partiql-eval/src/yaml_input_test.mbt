///|
test "YAML bindings support SELECT over exact YAML data" {
  let source = "t: [{a: 2}, {a: 3}]\nn: 9223372036854775808"
  let env = @eval.Bindings::from_yaml_text(source)
  let bytes_env = @eval.Bindings::from_yaml_bytes(@utf8.encode(source))
  @expect.expect_all(soft => {
    soft
    .expect(@eval.evaluate_text("SELECT VALUE r.a + 1 FROM t AS r", env~))
    .to_equal(@partiql_ion.read_text("$bag::[3,4]")[0])
    soft
    .expect(@eval.evaluate_text("n", env~))
    .to_equal(@eval.evaluate_text("n", env=bytes_env))
    soft
    .expect_call(() => @eval.Bindings::from_yaml_text("[]"))
    .to_raise_matching(
      e => e is @partiql_yaml.YamlError::YamlError(kind=Bindings, ..),
      description="object environment",
    )
  })
}

///|
test "YAML bindings distinguish a stream from a mapping environment" {
  @expect.expect_all(soft => {
    for source in ["", "[]", "null", "--- {x: 1}\n--- {x: 2}"] {
      soft
      .expect_call(() => @eval.Bindings::from_yaml_text(source))
      .to_raise_matching(
        e => e is @partiql_yaml.YamlError::YamlError(kind=Bindings, ..),
        description="exactly one mapping",
      )
    }
    for
      (source, expected) in [
        ("", "$bag::[]"),
        ("---", "null"),
        ("--- 1\n--- 2", "$bag::[1, 2]"),
      ] {
      let env = @eval.Bindings::empty().with_data(
        "t",
        @partiql_yaml.read_text(source),
      )
      soft
      .expect(@eval.evaluate_text("t", env~))
      .to_equal(@partiql_ion.read_text(expected)[0])
    }
  })
}
