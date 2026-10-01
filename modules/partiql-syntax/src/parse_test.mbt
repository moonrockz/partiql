///|
test "parse returns the syntax tree of a statement" {
  match @syntax.parse("SELECT a FROM t WHERE a > 1") {
    Query({ body: Select(s), .. }) =>
      @expect.expect(s.where_ is Some(_)).to_be_true()
    other => fail("unexpected \{@debug.to_string(other)}")
  }
}

///|
test "parse errors: Syntax for invalid input, Unsupported for graph MATCH" {
  @expect.expect_all(soft => {
    soft
    .expect_call(() => @syntax.parse("SELECT"))
    .to_raise_matching(
      e => e is @syntax.ParseError::Syntax(_),
      description="Syntax",
    )
    soft
    .expect_call(() => @syntax.parse("SELECT * FROM (g MATCH (x))"))
    .to_raise_matching(
      e => e is @syntax.ParseError::Unsupported(_),
      description="Unsupported",
    )
  })
}
