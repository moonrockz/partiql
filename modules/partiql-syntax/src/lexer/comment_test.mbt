///|
test "lex_with_comments returns the comments in source order" {
  let source = "SELECT -- one\n a /* two */ FROM t -- three\r\n"
  let (tokens, comments) = @lexer.lex_with_comments(source)
  @expect.expect_all(soft => {
    soft
    .expect(tokens.map(t => t.kind))
    .to_equal(@lexer.lex(source).map(t => t.kind))
    soft
    .expect(comments.map(c => c.text))
    .to_equal(["-- one", "/* two */", "-- three"])
    soft.expect(comments.map(c => c.kind)).to_equal([Line, Block, Line])
    soft
    .expect(
      comments.map(c => {
        source.view(start_offset=c.span.start, end_offset=c.span.end).to_owned()
      }),
    )
    .to_equal(["-- one", "/* two */", "-- three"])
  })
}

///|
test "a comment at the end of input without a line break" {
  let (_, comments) = @lexer.lex_with_comments("SELECT 1 -- last")
  @expect.expect(comments.map(c => c.text)).to_equal(["-- last"])
}
