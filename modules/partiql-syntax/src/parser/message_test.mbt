///|
/// The message and `found` of the error that `source` raises.
fn failure(source : String) -> (String, String) raise {
  try @parser.parse_statement(source) catch {
    Syntax(message~, found~, ..) => (message, found)
    Unsupported(message~, ..) => (message, "")
  } noraise {
    _ => fail("no error for \{source}")
  }
}

///|
test "found names keywords, identifiers and literals" {
  @expect.expect_all(soft => {
    soft
    .expect(failure("SELECT FROM t"))
    .to_equal(("expected an expression", "keyword `FROM`"))
    soft
    .expect(failure("SELECT a, FROM t"))
    .to_equal(("expected an expression", "keyword `FROM`"))
    soft
    .expect(failure("SELECT a FROM t ORDER a"))
    .to_equal(("expected BY", "identifier `a`"))
    soft
    .expect(failure("SELECT (a FROM t"))
    .to_equal(("expected `)`", "keyword `FROM`"))
    soft.expect(failure("SELECT a FROM t t2 t3").1).to_equal("identifier `t3`")
    soft
    .expect(failure("SELECT a \"b\" \"c\"").1)
    .to_equal("identifier `\"c\"`")
    soft.expect(failure("SELECT a FROM t 'x'").1).to_equal("string `'x'`")
    soft
    .expect(failure("SELECT a FROM t 'abcdefghijklmnopqrstuvwxyz'").1)
    .to_equal("string `'abcdefghijklmnopqrst…'`")
    soft.expect(failure("SELECT a FROM t 42").1).to_equal("number `42`")
    soft.expect(failure("SELECT a FROM t )").1).to_equal("`)`")
    soft.expect(failure("SELECT a FROM").1).to_equal("end of input")
  })
}
