// Temporary hooks; Tasks 5 and 6 replace them.

///|
fn Parser::query(self : Parser) -> @ast.Query raise @ast.ParseError {
  raise @ast.ParseError::Unsupported(message="queries", span=self.peek().span)
}

///|
pub fn parse_statement(source : String) -> @ast.Statement raise @ast.ParseError {
  let p = Parser::new(@lexer.lex(source))
  Query(p.query())
}
