///|
/// An expression kind and its half-open UTF-16 source span.
/// Recovered expressions may contain `ExprKind::Error`.
#derive(Debug, Eq)
pub(all) struct Expr {
  kind : ExprKind
  span : Span
}

///|
/// The unary numeric signs `+` and `-`.
#derive(Debug, Eq)
pub(all) enum UnaryOp {
  Pos
  Neg
}

///|
/// A non-short-circuit arithmetic, concatenation or comparison operator.
/// AND, OR and NOT have separate expression variants.
#derive(Debug, Eq)
pub(all) enum BinaryOp {
  Add
  Sub
  Mul
  Div
  Mod
  Concat
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
}

///|
/// Which end of a string TRIM removes matching characters from.
#derive(Debug, Eq)
pub(all) enum TrimSpec {
  Both
  Leading
  Trailing
}

///|
/// A datetime field used by EXTRACT, DATE_ADD, DATE_DIFF and interval qualifiers.
/// Not every field is valid in every position; the parser checks those rules.
#derive(Debug, Eq)
pub(all) enum DatetimeField {
  Year
  Month
  Day
  Hour
  Minute
  Second
  TimezoneHour
  TimezoneMinute
}

///|
/// The SQL clock functions (SQL-92 6.8).
#derive(Debug, Eq)
pub(all) enum CurrentKind {
  Date
  Time
  Timestamp
}

///|
/// The syntactic form of an expression, with child expressions in source order.
/// Literal source text and syntactic options are retained for printing.
/// Parsing a form does not imply the evaluator supports it.
#derive(Debug, Eq)
pub(all) enum ExprKind {
  Lit(Literal)
  /// A variable; `qualified` is the `@` prefix (local-first lookup).
  VarRef(Identifier, qualified~ : Bool)
  /// `?`
  Parameter
  Path(Expr, Array[PathStep])
  Unary(UnaryOp, Expr)
  Binary(BinaryOp, Expr, Expr)
  And(Expr, Expr)
  Or(Expr, Expr)
  Not(Expr)
  /// `IS [NOT] TRUE | FALSE | UNKNOWN`; `None` is UNKNOWN.
  BoolTest(Expr, Bool?, negated~ : Bool)
  Like(Expr, pattern~ : Expr, escape~ : Expr?, negated~ : Bool)
  Between(Expr, low~ : Expr, high~ : Expr, negated~ : Bool)
  In(Expr, Expr, negated~ : Bool)
  IsNull(Expr, negated~ : Bool)
  IsMissing(Expr, negated~ : Bool)
  IsType(Expr, DataType, negated~ : Bool)
  Overlaps(Expr, Expr)
  Case(operand~ : Expr?, branches~ : Array[(Expr, Expr)], default~ : Expr?)
  Cast(Expr, DataType)
  Extract(DatetimeField, Expr)
  Trim(spec~ : TrimSpec?, chars~ : Expr?, Expr)
  Substring(Expr, start~ : Expr, length~ : Expr?)
  /// `POSITION(needle IN haystack)`
  Position(Expr, Expr)
  Overlay(Expr, placing~ : Expr, from~ : Expr, for_~ : Expr?)
  Coalesce(Array[Expr])
  NullIf(Expr, Expr)
  DateAdd(DatetimeField, Expr, Expr)
  DateDiff(DatetimeField, Expr, Expr)
  /// `CURRENT_DATE`, `CURRENT_TIME [(p)]`, `CURRENT_TIMESTAMP [(p)]`.
  CurrentDatetime(CurrentKind, precision~ : Int32?)
  Call(Identifier, Array[Expr], quantifier~ : SetQuantifier?)
  /// `name(*)`, for example `COUNT(*)`
  CallStar(Identifier)
  List(Array[Expr])
  Bag(Array[Expr])
  Sexp(Array[Expr])
  Struct(Array[(Expr, Expr)])
  Map(Array[(Expr, Expr)])
  /// `ROW(...)` and `(a, b)`
  Row(Array[Expr])
  /// `VALUES (..), (..)`; each value is a `Row`.
  Values(Array[Expr])
  /// A subquery.
  Query(Query)
  /// `(graph MATCH pattern)` (GPML).
  GraphMatch(GraphMatch)
  /// A missing or broken expression in a recovered tree (spec M3d); its span
  /// covers the skipped tokens.
  Error
}

///|
/// One field, index or wildcard step following a path root.
/// Identifiers retain whether lookup is case-sensitive.
#derive(Debug, Eq)
pub(all) enum PathStep {
  /// `.name`
  Field(Identifier)
  /// `.'name'`
  FieldString(String, span~ : Span)
  /// `[expr]`
  Index(Expr)
  /// `[*]`
  AllElements(Span)
  /// `.*`
  AllFields(Span)
}

///|
/// The leading and optional trailing fields of an INTERVAL type or literal.
/// Optional precisions retain the written leading and fractional digit counts.
#derive(Debug, Eq)
pub(all) struct IntervalQualifier {
  start : DatetimeField
  start_precision : Int32?
  end : DatetimeField?
  fractional_precision : Int32?
}

///|
/// A literal. Numbers keep their source text; an Ion literal keeps its text
/// and its parsed value.
#derive(Debug)
pub(all) enum Literal {
  Null
  Missing
  Bool(Bool)
  Int(String)
  Decimal(String)
  Float(String)
  String(String)
  Ion(String, @ion_core.IonValue)
  Date(String)
  Time(String, precision~ : Int32?, with_tz~ : Bool)
  Timestamp(String, precision~ : Int32?, with_tz~ : Bool)
  Interval(String, negative~ : Bool, qualifier~ : IntervalQualifier)
}

///|
pub impl Eq for Literal with fn equal(a, b) {
  match (a, b) {
    (Ion(x, xv), Ion(y, yv)) => x == y && xv.equals(yv)
    (Null, Null) | (Missing, Missing) => true
    (Bool(x), Bool(y)) => x == y
    (Int(x), Int(y)) | (Decimal(x), Decimal(y)) | (Float(x), Float(y)) => x == y
    (String(x), String(y)) | (Date(x), Date(y)) => x == y
    (Time(x, precision=p, with_tz=z), Time(y, precision=q, with_tz=w))
    | (
      Timestamp(x, precision=p, with_tz=z),
      Timestamp(y, precision=q, with_tz=w),
    ) => x == y && p == q && z == w
    (Interval(x, negative=n, qualifier=q), Interval(y, negative=m, qualifier=r)) =>
      x == y && n == m && q == r
    _ => false
  }
}
