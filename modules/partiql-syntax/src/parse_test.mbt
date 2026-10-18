///|
test "parse returns the syntax tree of a statement" {
  match @syntax.parse("SELECT a FROM t WHERE a > 1") {
    Query({ body: Select(s), .. }) =>
      @expect.expect(s.where_ is Some(_)).to_be_true()
    other => fail("unexpected \{@debug.to_string(other)}")
  }
}

///|
test "parse errors: Syntax for invalid input; graph MATCH parses" {
  @expect.expect_all(soft => {
    soft
    .expect_call(() => @syntax.parse("SELECT"))
    .to_raise_matching(
      e => e is @syntax.ParseError::Syntax(_),
      description="Syntax",
    )
    soft
    .expect_call(() => @syntax.parse("SELECT * FROM (g MATCH (x))"))
    .not()
    .to_raise()
  })
}

///|
test "Ion literals beyond the former reader limit parse and print" {
  @expect.expect_all(soft => {
    for (open, close) in [("[", "]"), ("(", ")"), ("{a:", "}"), ("a::[", "]")] {
      let source = "`" + open.repeat(1024) + "0" + close.repeat(1024) + "`"
      soft.expect(@syntax.print(@syntax.parse(source))).to_equal(source)
    }
  })
}

///|
test "Ion literals at the former reader limit still parse and print" {
  @expect.expect_all(soft => {
    for (open, close) in [("[", "]"), ("(", ")"), ("{a:", "}"), ("a::[", "]")] {
      let source = "`" + open.repeat(128) + "0" + close.repeat(128) + "`"
      let statement = @syntax.parse(source)
      soft.expect(@syntax.print(statement)).to_equal(source)
    }
  })
}

///|
test "very deep malformed Ion literals report errors and recover to the next statement" {
  @expect.expect_all(soft => {
    for (open, close) in [("[", "]"), ("(", ")"), ("{a:", "}"), ("a::[", "]")] {
      let literal = "`" + open.repeat(200000) + "0" + close.repeat(199999) + "`"
      let source = "SELECT " + literal + "; SELECT 2"
      let strict = try @syntax.parse(source) catch {
        e => e
      } noraise {
        _ => fail("expected malformed Ion to raise Syntax")
      }
      soft
      .expect(
        strict is @syntax.ParseError::Syntax(message~, span~, ..) &&
        message.has_prefix("invalid Ion literal:") &&
        span == { start: 7, end: 7 + literal.length(), },
      )
      .to_be_true()
      let recovered = @syntax.parse_script_recovering(source)
      soft.expect(recovered.errors).to_equal([strict])
      soft.expect(recovered.script.statements.length()).to_equal(2)
      soft
      .expect(recovered.script.statements.get(1).map(s => @syntax.print(s)))
      .to_equal(Some("SELECT 2"))
    }
  })
}
