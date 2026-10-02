///|
pub using @ast {
  type Statement,
  type ParseError,
  type Span,
  type Script,
  type Comment,
  type CommentKind,
}

///|
/// Parses one PartiQL statement: a query, with an optional final `;`.
/// Raises `ParseError::Syntax` for invalid input and `ParseError::Unsupported`
/// for valid input that this version does not parse yet (reserved for later
/// milestones; nothing raises it since M2b).
pub fn parse(source : String) -> Statement raise ParseError {
  @parser.parse_statement(source)
}

///|
/// Parses a script: statements separated by `;`, with its comments.
pub fn parse_script(source : String) -> Script raise ParseError {
  @parser.parse_script(source)
}

///|
/// The canonical text of a statement (no comments, no final `;`).
pub fn print(statement : Statement) -> String {
  @printer.print(statement)
}

///|
/// The canonical text of a script, with its comments.
pub fn print_script(script : Script) -> String {
  @printer.print_script(script)
}

///|
/// Parses `source` as a script and prints it in canonical form, keeping the
/// comments.
pub fn format(source : String) -> String raise ParseError {
  @printer.print_script(@parser.parse_script(source))
}
