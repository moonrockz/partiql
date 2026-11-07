///|
/// A parsed statement. M2 parses queries (DQL).
#derive(Debug, Eq)
pub(all) enum Statement {
  Query(Query)
  /// A statement that error recovery could not read (spec M3d).
  Error(Span)
}

///|
/// An identifier: a regular name (case-insensitive) or a delimited `"name"`
/// (case-sensitive).
#derive(Debug, Eq)
pub(all) struct Identifier {
  text : String
  delimited : Bool
  span : Span
}

///|
/// An explicit ALL or DISTINCT keyword. A surrounding `None` means the
/// keyword was omitted; its default depends on the clause.
#derive(Debug, Eq)
pub(all) enum SetQuantifier {
  All
  Distinct
}

///|
/// A query: an optional WITH, a body, and the clauses that apply to the
/// whole body.
#derive(Debug, Eq)
pub(all) struct Query {
  with_ : Array[WithBinding]
  body : QueryBody
  order_by : Array[SortSpec]
  limit : Expr?
  offset : Expr?
  span : Span
}

///|
/// A named query in a WITH clause, with its complete source span.
#derive(Debug, Eq)
pub(all) struct WithBinding {
  name : Identifier
  query : Query
  span : Span
}

///|
/// The body before ORDER BY, LIMIT and OFFSET: a SELECT/PIVOT, set
/// operation, scalar expression or TABLE reference.
#derive(Debug, Eq)
pub(all) enum QueryBody {
  Select(Select)
  SetOp(SetOp)
  Expr(Expr)
  /// `TABLE name` (RFC 0007): a table name such as `t` or `hr.employees`,
  /// one identifier per part. Never empty.
  Table(Array[Identifier])
}

///|
/// The UNION, INTERSECT and EXCEPT set operations.
#derive(Debug, Eq)
pub(all) enum SetOpKind {
  Union
  Intersect
  Except
}

///|
/// `CORRESPONDING [BY (names)]` (RFC 0007).
#derive(Debug, Eq)
pub(all) enum Corresponding {
  All
  By(Array[Identifier])
}

///|
/// A binary set operation, retaining its quantifier, OUTER flag and optional
/// CORRESPONDING clause. Each operand is a complete query.
#derive(Debug, Eq)
pub(all) struct SetOp {
  op : SetOpKind
  quantifier : SetQuantifier?
  outer : Bool
  corresponding : Corresponding?
  left : Query
  right : Query
  span : Span
}

///|
/// A SELECT (or PIVOT) block.
#derive(Debug, Eq)
pub(all) struct Select {
  quantifier : SetQuantifier?
  projection : Projection
  from : FromItem?
  let_ : Array[LetBinding]
  where_ : Expr?
  group_by : GroupBy?
  having : Expr?
  span : Span
}

///|
/// The output form of SELECT or PIVOT. A value projection produces values;
/// a SELECT list or star describes tuple attributes.
#derive(Debug, Eq)
pub(all) enum Projection {
  Star(Span)
  Items(Array[SelectItem])
  Value(Expr)
  Pivot(value~ : Expr, key~ : Expr)
}

///|
/// An expression with an optional output alias, or an attribute expansion.
/// `span` covers the item including its alias.
#derive(Debug, Eq)
pub(all) enum SelectItem {
  Expr(Expr, as_~ : Identifier?, span~ : Span)
  /// `expr.*`
  AllFields(Expr, span~ : Span)
}

///|
/// A FROM source, UNPIVOT source or recursive join tree.
#derive(Debug, Eq)
pub(all) enum FromItem {
  Scan(FromSource)
  Unpivot(FromSource)
  Join(Join)
}

///|
/// A FROM source with its `AS`, `AT` and `BY` variables.
#derive(Debug, Eq)
pub(all) struct FromSource {
  /// `LATERAL` (spec section 5.7)
  lateral : Bool
  expr : Expr
  as_ : Identifier?
  at : Identifier?
  by : Identifier?
  span : Span
}

///|
/// The requested join kind, including NULL-padding outer joins.
#derive(Debug, Eq)
pub(all) enum JoinKind {
  Inner
  Left
  Right
  Full
}

///|
/// How a join is written: comma, CROSS JOIN or JOIN with an ON expression.
#derive(Debug, Eq)
pub(all) enum JoinForm {
  /// `a, b`
  Comma
  /// `a [kind] CROSS JOIN b`
  Cross
  /// `a [kind] JOIN b ON condition`
  On(Expr)
}

///|
/// A binary FROM join with its kind, spelling and complete source span.
#derive(Debug, Eq)
pub(all) struct Join {
  kind : JoinKind
  form : JoinForm
  left : FromItem
  right : FromItem
  span : Span
}

///|
/// A LET expression and its required variable name. Bindings are stored
/// in source order so later expressions can refer to earlier variables.
#derive(Debug, Eq)
pub(all) struct LetBinding {
  expr : Expr
  name : Identifier
  span : Span
}

///|
/// Grouping keys plus an optional GROUP AS variable and the clause span.
#derive(Debug, Eq)
pub(all) struct GroupBy {
  keys : GroupKeys
  group_as : Identifier?
  span : Span
}

///|
/// GROUP ALL or an ordered list of GROUP BY keys, retaining PARTIAL.
#derive(Debug, Eq)
pub(all) enum GroupKeys {
  /// `GROUP ALL` (spec section 11): one group of all rows.
  All
  /// `GROUP [PARTIAL] BY keys`
  By(Array[GroupKey], partial~ : Bool)
}

///|
/// A grouping expression and its optional explicit alias.
#derive(Debug, Eq)
pub(all) struct GroupKey {
  expr : Expr
  as_ : Identifier?
  span : Span
}

///|
/// An explicit ASC or DESC direction. An omitted direction is stored as None.
#derive(Debug, Eq)
pub(all) enum SortOrder {
  Asc
  Desc
}

///|
/// An explicit NULLS FIRST or NULLS LAST choice. Omission stays None.
#derive(Debug, Eq)
pub(all) enum NullsOrder {
  First
  Last
}

///|
/// One ORDER BY expression with optional direction and null-placement keywords.
#derive(Debug, Eq)
pub(all) struct SortSpec {
  expr : Expr
  order : SortOrder?
  nulls : NullsOrder?
  span : Span
}
