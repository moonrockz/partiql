///|
fn kinds(source : String) -> Array[@lexer.TokenKind] raise {
  @lexer.lex(source).map(t => t.kind)
}

///|
fn syntax_error(e : Error) -> Bool {
  e is @ast.ParseError::Syntax(_)
}

///|
test "words, identifiers, strings and numbers" {
  @expect.expect_all(soft => {
    soft
    .expect(kinds("SeLeCt x_1 $y \"Q \"\"x\"\"\" 'it''s'"))
    .to_equal([
      Word("SeLeCt"),
      Word("x_1"),
      Word("$y"),
      QuotedIdent("Q \"x\""),
      StringLit("it's"),
      End,
    ])
    soft
    .expect(kinds("1 1. .5 1.5e-3 2E10 12345678901234567890123456789"))
    .to_equal([
      IntLit("1"),
      DecimalLit("1."),
      DecimalLit(".5"),
      FloatLit("1.5e-3"),
      FloatLit("2E10"),
      IntLit("12345678901234567890123456789"),
      End,
    ])
  })
}

///|
test "punctuation is one token per character with exact spans" {
  let tokens = @lexer.lex("<<<<>>>>")
  @expect.expect_all(soft => {
    soft.expect(tokens.length()).to_equal(9)
    soft.expect(tokens[3].span).to_equal({ start: 3, end: 4, })
    soft
    .expect(kinds("a<-1"))
    .to_equal([Word("a"), Punct('<'), Punct('-'), IntLit("1"), End])
    soft
    .expect(kinds("( ) [ ] { } , . ; : * / % + - < > = ! | ~ ? @ & ^"))
    .to_equal(
      "()[]{},.;:*/%+-<>=!|~?@&^"
      .to_array()
      .map(c => @lexer.TokenKind::Punct(c)) +
      [End],
    )
  })
}

///|
test "comments are skipped" {
  @expect.expect(kinds("a -- note\n/* block\n */ b")).to_equal([
    Word("a"),
    Word("b"),
    End,
  ])
}

///|
test "Ion literals are scanned Ion-aware" {
  @expect.expect_all(soft => {
    soft.expect(kinds("`{a: \"x`y\"}`")).to_equal([IonLit("{a: \"x`y\"}"), End])
    soft.expect(kinds("`/* ` */ 1`")).to_equal([IonLit("/* ` */ 1"), End])
    soft.expect(kinds("`'''a`b'''`")).to_equal([IonLit("'''a`b'''"), End])
    soft.expect(kinds("`'q`x'`")).to_equal([IonLit("'q`x'"), End])
    soft.expect(kinds("`{{\"c\"}}`")).to_equal([IonLit("{{\"c\"}}"), End])
    soft.expect(kinds("`1 // `\n`")).to_equal([IonLit("1 // `\n"), End])
  })
}

///|
test "lexical errors raise Syntax" {
  @expect.expect_all(soft => {
    for source in ["'open", "/* open", "`open", "`{a:`", "a # b", "\"open"] {
      soft
      .expect_call(() => @lexer.lex(source), label=source)
      .to_raise_matching(syntax_error, description="Syntax")
    }
  })
}

///|
test "spans count UTF-16 code units" {
  let tokens = @lexer.lex("'\u{1F600}' x")
  @expect.expect_all(soft => {
    soft.expect(tokens[0].span).to_equal({ start: 0, end: 4, })
    soft.expect(tokens[1].span).to_equal({ start: 5, end: 6, })
    soft.expect(tokens[2].span).to_equal({ start: 6, end: 6, })
  })
}

///|
test "token descriptions" {
  @expect.expect_all(soft => {
    soft
    .expect(@lexer.TokenKind::Word("foo").describe())
    .to_equal("identifier foo")
    soft.expect(@lexer.TokenKind::Punct('(').describe()).to_equal("'('")
    soft.expect(@lexer.TokenKind::End.describe()).to_equal("end of input")
  })
}
