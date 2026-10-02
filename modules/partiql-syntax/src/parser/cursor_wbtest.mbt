///|
fn parser_of(source : String) -> Parser raise {
  Parser::new(@lexer.lex(source))
}

///|
test "composed operators need touching tokens" {
  @expect.expect_all(soft => {
    soft.expect(parser_of("<< x").at_op("<<")).to_be_true()
    soft.expect(parser_of("< < x").at_op("<<")).to_be_false()
    soft.expect(parser_of("<= x").at_op("<=")).to_be_true()
    soft.expect(parser_of("<> x").at_op("<>")).to_be_true()
    soft.expect(parser_of("!= x").at_op("!=")).to_be_true()
    soft.expect(parser_of("|| x").at_op("||")).to_be_true()
    soft.expect(parser_of("< x").at_op("<")).to_be_true()
  })
}

///|
test "eat_op consumes every token of the operator" {
  let p = parser_of(">> x")
  @expect.expect_all(soft => {
    soft.expect(p.eat_op(">>")).to_be_true()
    soft.expect(p.peek().kind).to_equal(Word("x"))
  })
}

///|
test "words match case-insensitively and errors list what was expected" {
  let p = parser_of("select")
  @expect.expect_all(soft => {
    soft.expect(p.at_word("FROM")).to_be_false()
    soft.expect(p.at_word("WHERE")).to_be_false()
    soft.expect(p.eat_word("SELECT")).to_be_true()
    soft
    .expect_call(() => p.expect_punct('('))
    .to_raise_matching(
      e => {
        e is @ast.ParseError::Syntax(expected=["`(`"], found="end of input", ..)
      },
      description="Syntax expecting '('",
    )
  })
}

///|
test "reserved words" {
  @expect.expect_all(soft => {
    for w in ["TRUE", "table", "Select", "VALUE", "TIME"] {
      soft.expect(is_reserved(w), label=w).to_be_true()
    }
    for w in ["count", "TRIM", "size", "exists", "foo", "year", "Second"] {
      soft.expect(is_reserved(w), label=w).to_be_false()
    }
  })
}

///|
test "identifiers reject reserved words, except path words after a dot" {
  @expect.expect_all(soft => {
    soft.expect(parser_of("foo").identifier().text).to_equal("foo")
    soft.expect(parser_of("\"Select\"").identifier().delimited).to_be_true()
    soft.expect_call(() => parser_of("true").identifier()).to_raise()
    soft
    .expect(parser_of("year").identifier(allow_path_words=true).text)
    .to_equal("year")
    soft
    .expect_call(() => parser_of("table").identifier(allow_path_words=true))
    .to_raise()
  })
}

///|
test "depth guard" {
  let p = parser_of("x")
  @expect.expect_call(() => {
    fn go(n : Int) -> Unit raise @ast.ParseError {
      p.nested(() => if n > 0 { go(n - 1) })
    }

    go(500)
  }).to_raise_matching(
    e => e is @ast.ParseError::Syntax(message="nesting is too deep", ..),
    description="nesting is too deep",
  )
}
