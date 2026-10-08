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
  Like(Expr, pattern~ : Expr, escape~ : Expr?, negated~ : Bool, @ast.Span)
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
  /// A FROM variable, by the name it was declared with.
  Local(String, @ast.Span)
  /// A name in a FROM source: the global of that name if there is one, else
  /// the FROM variable `variable` (partiql-tests select.ion,
  /// `joinWithShadowedGlobal`; `@name` selects the variable only).
  GlobalOrLocal(String, variable~ : String, delimited~ : Bool, @ast.Span)
  /// A query block: the projection of each binding tuple of `rel`, as a bag.
  Select(Rel, Projection, distinct~ : Bool, @ast.Span)
} derive(Debug)

///|
/// A relational plan node (spec M4b1 §3): it produces binding tuples.
pub(all) enum Rel {
  /// One binding of `as_` per element of a collection; `at` binds the
  /// element's position.
  Scan(Expr, as_~ : String, at~ : String?, @ast.Span)
  /// One binding of `as_` per attribute value of a tuple; `at` binds the
  /// attribute name.
  Unpivot(Expr, as_~ : String, at~ : String?, @ast.Span)
  /// The binding tuples for which the predicate is TRUE.
  Filter(Rel, Expr, @ast.Span)
  /// The pairs of a left and a right binding tuple. The right side sees the
  /// variables of the left (lateral), except for `Right`. `on` is `None` when
  /// every pair matches. `Left` and `Right` pad the side that finds no match
  /// with NULL.
  Join(JoinKind, Rel, Rel, on~ : Expr?, @ast.Span)
} derive(Debug)

///|
pub(all) enum JoinKind {
  Cross
  Inner
  Left
  Right
} derive(Debug, Eq)

///|
/// What a query block makes of each binding tuple.
pub(all) enum Projection {
  /// `SELECT VALUE e`
  Value(Expr)
} derive(Debug)
