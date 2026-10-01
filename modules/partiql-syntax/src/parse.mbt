///|
pub using @ast {type Statement, type ParseError, type Span}

///|
/// Parses one PartiQL statement: a query, with an optional final `;`.
/// Raises `ParseError::Syntax` for invalid input and `ParseError::Unsupported`
/// for valid input that this version does not parse yet (graph MATCH).
pub fn parse(source : String) -> Statement raise ParseError {
  @parser.parse_statement(source)
}
