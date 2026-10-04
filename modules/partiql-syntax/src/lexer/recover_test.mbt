///|
fn messages(errors : Array[@ast.ParseError]) -> Array[String] {
  errors.map(e => {
    match e {
      Syntax(message~, ..) | Unsupported(message~, ..) => message
    }
  })
}

///|
fn token_names(tokens : Array[@lexer.Token]) -> Array[String] {
  tokens.map(t => {
    match t.kind {
      Invalid => "invalid"
      End => "end"
      Word(w) => w
      _ => "other"
    }
  })
}

///|
test "the recovering lexer records errors and continues" {
  @expect.expect_all(soft => {
    let (tokens, _, errors) = @lexer.lex_recovering("SELECT a § b # c")
    soft
    .expect(messages(errors))
    .to_equal(["unexpected character `§`", "unexpected character `#`"])
    soft.expect(token_names(tokens)).to_equal(["SELECT", "a", "b", "c", "end"])
    let (tokens, _, errors) = @lexer.lex_recovering(
      "SELECT `{a: }` FROM t WHERE x = `[1,`",
    )
    soft.expect(errors.length()).to_equal(2)
    soft
    .expect(token_names(tokens))
    .to_equal([
      "SELECT", "invalid", "FROM", "t", "WHERE", "x", "other", "invalid", "end",
    ])
    let (tokens, _, errors) = @lexer.lex_recovering("SELECT `abc")
    soft.expect(messages(errors)).to_equal(["unterminated Ion literal"])
    soft.expect(token_names(tokens)).to_equal(["SELECT", "invalid", "end"])
    let (tokens, _, errors) = @lexer.lex_recovering("SELECT 'abc")
    soft.expect(messages(errors)).to_equal(["unterminated string"])
    soft.expect(token_names(tokens)).to_equal(["SELECT", "invalid", "end"])
    let (tokens, _, errors) = @lexer.lex_recovering("SELECT \"abc")
    soft.expect(messages(errors)).to_equal(["unterminated quoted identifier"])
    soft.expect(token_names(tokens)).to_equal(["SELECT", "invalid", "end"])
    let (_, comments, errors) = @lexer.lex_recovering("SELECT 1 /* open")
    soft.expect(messages(errors)).to_equal(["unterminated comment"])
    soft.expect(comments.length()).to_equal(0)
    let (tokens, _, errors) = @lexer.lex_recovering("`\"a`b\"`")
    soft.expect(errors).to_equal([])
    soft.expect(token_names(tokens)).to_equal(["other", "end"])
    let (_, _, errors) = @lexer.lex_recovering("#".repeat(150))
    soft.expect(errors.length()).to_equal(100)
    let (tokens, _, errors) = @lexer.lex_recovering("a \u{1} b")
    soft.expect(messages(errors)).to_equal(["unexpected character U+0001"])
    soft.expect(token_names(tokens)).to_equal(["a", "b", "end"])
  })
}

///|
test "the strict error is the first recovering error" {
  @expect.expect_all(soft => {
    for
      source in [
        "SELECT a # b", "SELECT 'x", "`{a:}` + `{b:}`", "a /* x", "SELECT a FROM t",
      ] {
      let strict = try @lexer.lex(source) catch {
        e => Some(e)
      } noraise {
        _ => None
      }
      let (_, _, errors) = @lexer.lex_recovering(source)
      soft.expect(errors.get(0)).to_equal(strict)
    }
  })
}
