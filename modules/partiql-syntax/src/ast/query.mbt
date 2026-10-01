///|
/// A parsed statement. M2 parses queries (DQL).
pub(all) enum Statement {
  Query(Query)
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
pub(all) struct WithBinding {
  name : Identifier
  query : Query
  span : Span
} derive(Debug, Eq)

///|
pub(all) enum QueryBody {
  Select(Select)
  SetOp(SetOp)
  Expr(Expr)
  /// `TABLE name` (RFC 0007): a table name such as `t` or `hr.employees`,
  /// one identifier per part. Never empty.
  Table(Array[Identifier])
} derive(Debug, Eq)

///|
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
pub(all) enum Projection {
  Star(Span)
  Items(Array[SelectItem])
  Value(Expr)
  Pivot(value~ : Expr, key~ : Expr)
} derive(Debug, Eq)

///|
pub(all) enum SelectItem {
  Expr(Expr, as_~ : Identifier?, span~ : Span)
  /// `expr.*`
  AllFields(Expr, span~ : Span)
} derive(Debug, Eq)

///|
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
pub(all) enum JoinKind {
  Inner
  Left
  Right
  Full
} derive(Debug, Eq)

///|
pub(all) enum JoinForm {
  /// `a, b`
  Comma
  /// `a [kind] CROSS JOIN b`
  Cross
  /// `a [kind] JOIN b ON condition`
  On(Expr)
} derive(Debug, Eq)

///|
pub(all) struct Join {
  kind : JoinKind
  form : JoinForm
  left : FromItem
  right : FromItem
  span : Span
} derive(Debug, Eq)

///|
pub(all) struct LetBinding {
  expr : Expr
  name : Identifier
  span : Span
} derive(Debug, Eq)

///|
pub(all) struct GroupBy {
  keys : GroupKeys
  group_as : Identifier?
  span : Span
} derive(Debug, Eq)

///|
pub(all) enum GroupKeys {
  /// `GROUP ALL` (spec section 11): one group of all rows.
  All
  /// `GROUP [PARTIAL] BY keys`
  By(Array[GroupKey], partial~ : Bool)
} derive(Debug, Eq)

///|
pub(all) struct GroupKey {
  expr : Expr
  as_ : Identifier?
  span : Span
} derive(Debug, Eq)

///|
pub(all) enum SortOrder {
  Asc
  Desc
} derive(Debug, Eq)

///|
pub(all) enum NullsOrder {
  First
  Last
} derive(Debug, Eq)

///|
pub(all) struct SortSpec {
  expr : Expr
  order : SortOrder?
  nulls : NullsOrder?
  span : Span
} derive(Debug, Eq)
