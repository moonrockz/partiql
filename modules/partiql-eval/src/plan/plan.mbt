///|
pub(all) enum Mode {
  Permissive
  Strict
} derive(Debug, Eq)

///|
pub(all) suberror EvalError {
  TypeError(message~ : String, span~ : @ast.Span)
  DataError(message~ : String, span~ : @ast.Span)
  Unsupported(message~ : String, span~ : @ast.Span)
  Syntax(@ast.ParseError)
} derive(Debug, Eq)

///|
/// A lowered scalar expression (spec M4a §3). Names are resolved, literals
/// are values.
pub(all) enum Expr {
  Const(@value.Value, @ast.Span)
  Global(String, delimited~ : Bool, @ast.Span)
  ListOf(Array[Expr], @ast.Span)
  BagOf(Array[Expr], @ast.Span)
  TupleOf(Array[(Expr, Expr)], @ast.Span)
  MapOf(Array[(Expr, Expr)], @ast.Span)
} derive(Debug)
