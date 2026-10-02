///|
fn lex_error(source : String) -> (String, Int, Int, String) raise {
  try @lexer.lex(source) catch {
    Syntax(message~, span~, found~, ..) =>
      (message, span.start, span.end, found)
    _ => fail("not a syntax error")
  } noraise {
    _ => fail("no error for \{source}")
  }
}

///|
test "lexer errors name the problem" {
  @expect.expect_all(soft => {
    soft
    .expect(lex_error("SELECT 'abc"))
    .to_equal(("unterminated string", 7, 8, ""))
    soft
    .expect(lex_error("SELECT \"abc"))
    .to_equal(("unterminated quoted identifier", 7, 8, ""))
    soft
    .expect(lex_error("SELECT 1 /* x"))
    .to_equal(("unterminated comment", 9, 11, ""))
    soft
    .expect(lex_error("SELECT `{a: 1} FROM t"))
    .to_equal(("unterminated Ion literal", 7, 8, ""))
    soft
    .expect(lex_error("SELECT # FROM t"))
    .to_equal(("unexpected character `#`", 7, 8, ""))
    let (message, start, end, found) = lex_error("SELECT `{a: }` FROM t")
    soft.expect(message.has_prefix("invalid Ion literal: ")).to_be_true()
    soft.expect(message.contains("Syntax(")).to_be_false()
    soft.expect((start, end, found)).to_equal((7, 14, ""))
  })
}

///|
test "lexer errors name astral and control characters safely" {
  @expect.expect_all(soft => {
    soft
    .expect(lex_error("SELECT 😀 FROM t"))
    .to_equal(("unexpected character `😀`", 7, 9, ""))
    soft
    .expect(lex_error("SELECT a\u{0}b"))
    .to_equal(("unexpected character U+0000", 8, 9, ""))
    soft
    .expect(lex_error("SELECT a\u{1b}b"))
    .to_equal(("unexpected character U+001B", 8, 9, ""))
  })
}
