///|
test "the M0 parser reports every statement as unsupported" {
  try @syntax.parse("SELECT * FROM t") catch {
    error =>
      @expect.expect(error).to_equal(
        @syntax.ParseError::Unsupported("parser not implemented"),
      )
  } noraise {
    statement =>
      fail("expected Unsupported, got \{@debug.to_string(statement)}")
  }
}
