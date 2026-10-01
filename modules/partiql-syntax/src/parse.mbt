///|
/// A parsed PartiQL statement.
///
/// M0 placeholder: it keeps only the source text. M2 replaces it with the AST.
pub(all) struct Statement {
  source : String
} derive(Debug, Eq)

///|
/// Why a statement could not be parsed.
pub(all) suberror ParseError {
  /// The parser does not support this input yet. Conformance checks count
  /// this as a failure, never as an expected syntax error.
  Unsupported(String)
  /// The input is not valid PartiQL. `offset` is a UTF-16 offset into the
  /// source.
  Syntax(message~ : String, offset~ : Int)
} derive(Debug, Eq)

///|
/// Parses one PartiQL statement.
pub fn parse(source : String) -> Statement raise ParseError {
  ignore(source)
  raise ParseError::Unsupported("parser not implemented")
}
