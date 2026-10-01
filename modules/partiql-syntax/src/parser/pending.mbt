// Temporary hooks; Tasks 5 and 6 replace them.

///|
fn Parser::datetime_literal(self : Parser) -> @ast.Expr raise @ast.ParseError {
  raise @ast.ParseError::Unsupported(
    message="datetime literals",
    span=self.peek().span,
  )
}

///|
fn Parser::special_form(
  self : Parser,
  name : String,
) -> @ast.Expr raise @ast.ParseError {
  raise @ast.ParseError::Unsupported(message=name, span=self.peek().span)
}

///|
fn Parser::query(self : Parser) -> @ast.Query raise @ast.ParseError {
  raise @ast.ParseError::Unsupported(message="queries", span=self.peek().span)
}

///|
pub fn parse_statement(source : String) -> @ast.Statement raise @ast.ParseError {
  let p = Parser::new(@lexer.lex(source))
  Query(p.query())
}
