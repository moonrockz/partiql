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

///|
fn expected_of(source : String) -> Array[String] raise {
  try @parser.parse_statement(source) catch {
    Syntax(expected~, ..) => expected
    _ => fail("not a syntax error")
  } noraise {
    _ => fail("no error for \{source}")
  }
}

///|
test "expected lists are curated" {
  @expect.expect_all(soft => {
    soft
    .expect(expected_of("SELECT FROM t"))
    .to_equal(["DISTINCT", "ALL", "`*`", "VALUE", "an expression"])
    soft
    .expect(expected_of("SELECT a FROM"))
    .to_equal(["LATERAL", "UNPIVOT", "an expression"])
    soft.expect(expected_of("SELECT 1 +")).to_equal(["an expression"])
    soft
    .expect(expected_of(" <-TIME"))
    .to_equal(["WITH", "TABLE", "SELECT", "PIVOT", "an expression"])
    soft.expect(expected_of("SELECT a FROM t ORDER a")).to_equal(["BY"])
    soft
    .expect(expected_of("SELECT (a FROM t"))
    .to_equal(["MATCH", "`,`", "`)`", "an operator"])
    soft
    .expect(expected_of("SELECT x BETWEEN 1 2 FROM t").contains("AND"))
    .to_be_true()
    soft
    .expect(expected_of("SELECT <<1, 2 FROM t").contains("`>>`"))
    .to_be_true()
    soft
    .expect(expected_of("(g MATCH (a)-[e->(b))"))
    .to_equal(["`:`", "WHERE", "`]`"])
    let after = expected_of("SELECT a FROM t t2 t3")
    soft.expect(after.contains("end of input")).to_be_true()
    soft
    .expect(
      after.contains("`<<`") || after.contains("`!=`") || after.contains("OR"),
    )
    .to_be_false()
  })
}

///|
test "statements that later milestones parse are Unsupported" {
  @expect.expect_all(soft => {
    for
      word in [
        "INSERT", "UPDATE", "DELETE", "REPLACE", "UPSERT", "REMOVE", "SET", "CREATE",
        "DROP", "EXEC", "EXPLAIN", "FROM",
      ] {
      let source = word.to_lower() + " x y"
      soft
      .expect_call(() => @parser.parse_statement(source), label=source)
      .to_raise_matching(
        e => {
          match e {
            @ast.ParseError::Unsupported(message~, span~) =>
              message == "\{word} statements are not supported yet" &&
              span == ({ start: 0, end: word.length(), } : @ast.Span)
            _ => false
          }
        },
        description="Unsupported",
      )
    }
    soft
    .expect_call(() => @parser.parse_script("SELECT 1; DELETE FROM t"))
    .to_raise_matching(
      e => e is @ast.ParseError::Unsupported(_),
      description="Unsupported",
    )
    soft
    .expect_call(() => @parser.parse_statement("replace('a')"))
    .not()
    .to_raise()
  })
}
