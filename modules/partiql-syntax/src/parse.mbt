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
/// for valid input that this version does not parse yet (DML and DDL
/// statements such as INSERT or CREATE, which later milestones parse).
pub fn parse(source : String) -> Statement raise ParseError {
  @parser.parse_statement(source)
}

///|
/// Parses a script: statements separated by `;`, with its comments.
pub fn parse_script(source : String) -> Script raise ParseError {
  @parser.parse_script(source)
}

///|
/// The text of a statement (no comments, no final `;`): canonical without
/// `width`, the pretty layout at `width` with it.
pub fn print(statement : Statement, width? : Int) -> String {
  @printer.print(statement, width?)
}

///|
/// The text of a script, with its comments: canonical without `width`, the
/// pretty layout at `width` with it.
pub fn print_script(script : Script, width? : Int) -> String {
  @printer.print_script(script, width?)
}

///|
/// Parses `source` as a script and prints it, keeping the comments:
/// canonical without `width`, the pretty layout at `width` with it.
pub fn format(source : String, width? : Int) -> String raise ParseError {
  @printer.print_script(@parser.parse_script(source), width?)
}

///|
pub using @diagnostic {type Position}

///|
/// The rendered diagnostic of a parse error (spec M3c §5).
pub fn render(
  error : ParseError,
  source : String,
  name~ : String,
  color? : Bool = false,
) -> String {
  @diagnostic.render(error, source, name~, color~)
}

///|
/// The 1-based line and code-point column of a UTF-16 offset.
pub fn position(source : String, offset : Int) -> Position {
  @diagnostic.position(source, offset)
}

///|
/// The S-expression of a statement (spec M3c §7).
pub fn to_sexp(statement : Statement, width? : Int = 80) -> String {
  @sexp.to_sexp(statement, width~)
}
