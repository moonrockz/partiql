///|
/// A parsed statement. M2 parses queries (DQL).
pub(all) enum Statement {
  Query(Query)
  /// A statement that error recovery could not read (spec M3d).
  Error(Span)
} derive(Debug, Eq)

///|
/// An identifier: a regular name (case-insensitive) or a delimited `"name"`
/// (case-sensitive).
pub(all) struct Identifier {
  text : String
  delimited : Bool
  span : Span
} derive(Debug, Eq)

///|
/// An explicit ALL or DISTINCT keyword. A surrounding `None` means the
/// keyword was omitted; its default depends on the clause.
pub(all) enum SetQuantifier {
  All
  Distinct
} derive(Debug, Eq)

///|
/// A query: an optional WITH, a body, and the clauses that apply to the
/// whole body.
pub(all) struct Query {
  with_ : Array[WithBinding]
  body : QueryBody
  order_by : Array[SortSpec]
  limit : Expr?
  offset : Expr?
  span : Span
} derive(Debug, Eq)

///|
/// A named query in a WITH clause, with its complete source span.
pub(all) struct WithBinding {
  name : Identifier
  query : Query
  span : Span
} derive(Debug, Eq)

///|
/// The body before ORDER BY, LIMIT and OFFSET: a SELECT/PIVOT, set
/// operation, scalar expression or TABLE reference.
pub(all) enum QueryBody {
  Select(Select)
  SetOp(SetOp)
  Expr(Expr)
  /// `TABLE name` (RFC 0007): a table name such as `t` or `hr.employees`,
  /// one identifier per part. Never empty.
  Table(Array[Identifier])
} derive(Debug, Eq)

///|
/// The UNION, INTERSECT and EXCEPT set operations.
pub(all) enum SetOpKind {
  Union
  Intersect
  Except
} derive(Debug, Eq)

///|
/// `CORRESPONDING [BY (names)]` (RFC 0007).
pub(all) enum Corresponding {
  All
  By(Array[Identifier])
} derive(Debug, Eq)

///|
/// A binary set operation, retaining its quantifier, OUTER flag and optional
/// CORRESPONDING clause. Each operand is a complete query.
pub(all) struct SetOp {
  op : SetOpKind
  quantifier : SetQuantifier?
  outer : Bool
  corresponding : Corresponding?
  left : Query
  right : Query
  span : Span
} derive(Debug, Eq)

///|
/// A SELECT (or PIVOT) block.
pub(all) struct Select {
  quantifier : SetQuantifier?
  projection : Projection
  from : FromItem?
  let_ : Array[LetBinding]
  where_ : Expr?
  group_by : GroupBy?
  having : Expr?
  span : Span
} derive(Debug, Eq)

///|
/// The output form of SELECT or PIVOT. A value projection produces values;
/// a SELECT list or star describes tuple attributes.
pub(all) enum Projection {
  Star(Span)
  Items(Array[SelectItem])
  Value(Expr)
  Pivot(value~ : Expr, key~ : Expr)
} derive(Debug, Eq)

///|
/// An expression with an optional output alias, or an attribute expansion.
/// `span` covers the item including its alias.
pub(all) enum SelectItem {
  Expr(Expr, as_~ : Identifier?, span~ : Span)
  /// `expr.*`
  AllFields(Expr, span~ : Span)
} derive(Debug, Eq)

///|
/// A FROM source, UNPIVOT source or recursive join tree.
pub(all) enum FromItem {
  Scan(FromSource)
  Unpivot(FromSource)
  Join(Join)
} derive(Debug, Eq)

///|
/// A FROM source with its `AS`, `AT` and `BY` variables.
pub(all) struct FromSource {
  /// `LATERAL` (spec section 5.7)
  lateral : Bool
  expr : Expr
  as_ : Identifier?
  at : Identifier?
  by : Identifier?
  span : Span
} derive(Debug, Eq)

///|
/// The requested join kind, including NULL-padding outer joins.
pub(all) enum JoinKind {
  Inner
  Left
  Right
  Full
} derive(Debug, Eq)

///|
/// How a join is written: comma, CROSS JOIN or JOIN with an ON expression.
pub(all) enum JoinForm {
  /// `a, b`
  Comma
  /// `a [kind] CROSS JOIN b`
  Cross
  /// `a [kind] JOIN b ON condition`
  On(Expr)
} derive(Debug, Eq)

///|
/// A binary FROM join with its kind, spelling and complete source span.
pub(all) struct Join {
  kind : JoinKind
  form : JoinForm
  left : FromItem
  right : FromItem
  span : Span
} derive(Debug, Eq)

///|
/// A LET expression and its required variable name. Bindings are stored
/// in source order so later expressions can refer to earlier variables.
pub(all) struct LetBinding {
  expr : Expr
  name : Identifier
  span : Span
} derive(Debug, Eq)

///|
/// Grouping keys plus an optional GROUP AS variable and the clause span.
pub(all) struct GroupBy {
  keys : GroupKeys
  group_as : Identifier?
  span : Span
} derive(Debug, Eq)

///|
/// GROUP ALL or an ordered list of GROUP BY keys, retaining PARTIAL.
pub(all) enum GroupKeys {
  /// `GROUP ALL` (spec section 11): one group of all rows.
  All
  /// `GROUP [PARTIAL] BY keys`
  By(Array[GroupKey], partial~ : Bool)
} derive(Debug, Eq)

///|
/// A grouping expression and its optional explicit alias.
pub(all) struct GroupKey {
  expr : Expr
  as_ : Identifier?
  span : Span
} derive(Debug, Eq)

///|
/// An explicit ASC or DESC direction. An omitted direction is stored as None.
pub(all) enum SortOrder {
  Asc
  Desc
} derive(Debug, Eq)

///|
/// An explicit NULLS FIRST or NULLS LAST choice. Omission stays None.
pub(all) enum NullsOrder {
  First
  Last
} derive(Debug, Eq)

///|
/// One ORDER BY expression with optional direction and null-placement keywords.
pub(all) struct SortSpec {
  expr : Expr
  order : SortOrder?
  nulls : NullsOrder?
  span : Span
} derive(Debug, Eq)
