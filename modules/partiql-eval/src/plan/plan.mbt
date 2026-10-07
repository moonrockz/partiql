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
/// One step of a path.
pub(all) enum Step {
  Field(String, delimited~ : Bool)
  Index(Expr)
  AllElements
  AllFields
} derive(Debug)

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
  Path(Expr, Array[Step], @ast.Span)
  IsNull(Expr, negated~ : Bool, @ast.Span)
  IsMissing(Expr, negated~ : Bool, @ast.Span)
  Unary(@ast.UnaryOp, Expr, @ast.Span)
  Binary(@ast.BinaryOp, Expr, Expr, @ast.Span)
  And(Expr, Expr, @ast.Span)
  Or(Expr, Expr, @ast.Span)
  Not(Expr, @ast.Span)
  /// `IS [NOT] TRUE | FALSE | UNKNOWN`; `None` is UNKNOWN.
  BoolTest(Expr, Bool?, negated~ : Bool, @ast.Span)
  Between(Expr, low~ : Expr, high~ : Expr, negated~ : Bool, @ast.Span)
  In(Expr, Expr, negated~ : Bool, @ast.Span)
  IsType(Expr, @ast.DataType, negated~ : Bool, @ast.Span)
  Case(
    operand~ : Expr?,
    branches~ : Array[(Expr, Expr)],
    default~ : Expr?,
    @ast.Span
  )
  Coalesce(Array[Expr], @ast.Span)
  NullIf(Expr, Expr, @ast.Span)
} derive(Debug)
