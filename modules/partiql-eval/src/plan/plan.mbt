///|
/// How the interpreter handles runtime type failures. Permissive mode yields
/// MISSING; strict mode raises `TypeError`. Data and unsupported-form failures
/// raise in either mode.
pub(all) enum Mode {
  Permissive
  Strict
} derive(Debug, Eq)

///|
/// An evaluation failure with a source location, or the original parse error.
/// `TypeError` is a strict-mode operand failure; `DataError` is invalid data or
/// a static error in either mode; `Unsupported` is an unimplemented form.
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
/// The local fallback of a FROM source after global lookup has failed.
pub(all) enum LocalLookup {
  Bound(String)
  Ambiguous(Array[String])
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
  /// `MAP { k: v, ... }`. A key or value type that every entry declares by
  /// CAST is known at lowering (spec M4d2 §3.3); otherwise it is inferred.
  MapOf(
    Array[(Expr, Expr)],
    key_type~ : @value.MapType?,
    value_type~ : @value.MapType?,
    @ast.Span
  )
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
  /// A built-in scalar function (spec M4d1 §2), with its arguments in the
  /// positions `Function` documents.
  Call(Function, Array[Expr], @ast.Span)
  /// `CAST(e AS T)` with its resolved target (spec M4d2 §3).
  Cast(Expr, @ops.CastTarget, @ast.Span)
  /// A FROM variable, by the name it was declared with.
  Local(String, @ast.Span)
  /// A name in a FROM source: the global of that name if there is one, else
  /// the local lookup `variable`, which may be ambiguous (partiql-tests select.ion,
  /// `joinWithShadowedGlobal`; `@name` selects the variable only).
  GlobalOrLocal(String, variable~ : LocalLookup, delimited~ : Bool, @ast.Span)
  /// A name that no variable declares, inside a query: the attribute of that
  /// name of the first tuple among the query variables `locals` (FROM AS and
  /// AT, and LET; innermost query first, each in declared order), else the
  /// global of that name, else MISSING (permissive) or a `TypeError`
  /// (strict).
  Implicit(String, delimited~ : Bool, locals~ : Array[String], @ast.Span)
  /// A query block: the projection of each binding tuple of `rel`, as a bag.
  Select(Rel, Projection, distinct~ : Bool, @ast.Span)
  /// A single-column `SELECT` (the first operand, a `Select`) used where a
  /// value is needed: see `SubqueryUse`.
  Subquery(Expr, SubqueryUse, @ast.Span)
  /// A query with ORDER BY, LIMIT or OFFSET over `body`: the elements of the
  /// body sorted by `order`: a list with ORDER BY, else a bag (a tuple for a
  /// PIVOT body). `aliases` are the output names that sort keys may use (a
  /// SELECT list's names, in order).
  Query(
    Expr,
    order~ : Array[SortKey],
    limit~ : Expr?,
    offset~ : Expr?,
    aliases~ : Array[String],
    @ast.Span
  )
  /// `left op right`, as a bag. `outer` is the PartiQL bag operator (OUTER);
  /// otherwise SQL rules apply: both operands are relations, matched by
  /// position or by `corresponding` (plan rulings 4-7). `all` keeps
  /// duplicates.
  SetOp(
    @ast.SetOpKind,
    all~ : Bool,
    outer~ : Bool,
    corresponding~ : @ast.Corresponding?,
    Expr,
    Expr,
    @ast.Span
  )
  /// `WITH name AS (query), ... body`: each binding is evaluated once, in
  /// order; later bindings and the body see the earlier ones as variables.
  With(Array[(String, Expr)], Expr, @ast.Span)
  /// `COLL_f(e)`: the aggregate of the elements of the collection `e`; NULL
  /// for NULL, MISSING for MISSING, a type failure for any other value.
  CollAggregate(AggregateKind, distinct~ : Bool, Expr, @ast.Span)
  /// A SQL aggregate `f(e)` (spec section 11.2.2): `e` evaluated for each
  /// member tuple of the group variable `group`, with each variable of
  /// `members` (the non-key FROM and LET variables) bound to the member's
  /// attribute of that name, then folded.
  Aggregate(
    AggregateKind,
    distinct~ : Bool,
    Expr,
    members~ : Array[String],
    group~ : String,
    @ast.Span
  )
  /// A key expression in a FROM source: a name there finds a global before
  /// a variable, so `otherwise` (the expression without key variables) when
  /// one of the names `globals` (name, delimited, span) is a global, else `key`.
  GlobalsFirst(
    Array[(String, Bool, @ast.Span)],
    key~ : Expr,
    otherwise~ : Expr,
    @ast.Span
  )
} derive(Debug)

///|
/// A key of ORDER BY. `nulls_first` is resolved: the explicit `NULLS FIRST`
/// or `NULLS LAST`, else NULL and MISSING come last for ASC and first for
/// DESC.
pub(all) struct SortKey {
  expr : Expr
  desc : Bool
  nulls_first : Bool
} derive(Debug)

///|
/// The variable that holds an output element for the sort keys of a query
/// whose body is not a SELECT. No identifier can name it.
pub let row_variable : String = "\u{0}row"

///|
/// The name of the frame that holds the output name `name` of a SELECT list
/// while ORDER BY runs: apart from every variable name.
pub fn output_variable(name : String) -> String {
  "\u{0}out:" + name
}

///|
/// How a single-column subquery is coerced at its use site.
/// Each variant defines its empty-input and cardinality behavior.
pub(all) enum SubqueryUse {
  /// One value: NULL for no row, the value of the column for one row, and
  /// for more rows MISSING (permissive) or a `TypeError` (strict).
  Scalar
  /// The bag of the value of the column of each row (`x IN (SELECT a ...)`).
  Column
  /// The attribute values of the only row, as a list (array coercion): NULL
  /// for no row; more rows as for `Scalar`.
  Row
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
  /// Each binding tuple with one more variable per `(name, expr)`, bound in
  /// order: an expression sees the variables before it (LET).
  Let(Rel, Array[(String, Expr)], @ast.Span)
  /// One binding tuple per group of the binding tuples of the input (spec
  /// section 11.1): the key variables and `group_as`, the bag of the member
  /// tuples of the group. A member tuple has one attribute per variable of
  /// `members` (FROM AS and AT, and LET, in order); a MISSING one is left
  /// out. Keys compare with `eqg` after MISSING becomes NULL.
  Group(Rel, Grouping, group_as~ : String, members~ : Array[String], @ast.Span)
} derive(Debug)

///|
/// A lowered join strategy. Left and right outer joins pad unmatched
/// bindings with NULL; cross and inner joins produce only matching pairs.
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
  /// `SELECT item, ...`: the attributes of one tuple.
  Items(Array[Item])
  /// `SELECT *`: the attributes of the tuple of each FROM variable `names`,
  /// in order.
  Star(Array[String])
  /// `PIVOT value AT key`: per row a one-attribute tuple (the empty tuple
  /// for a row without an attribute); the query joins them into one tuple.
  Pivot(value~ : Expr, key~ : Expr)
} derive(Debug)

///|
/// An item of a SELECT list.
pub(all) enum Item {
  /// `expr AS name`, the name given or implied.
  Named(String, Expr)
  /// `expr.*`
  AllFields(Expr)
} derive(Debug)

///|
/// Where an expression is in the source.
pub fn Expr::span(self : Expr) -> @ast.Span {
  match self {
    Const(_, span)
    | Global(_, delimited=_, span)
    | ListOf(_, span)
    | BagOf(_, span)
    | TupleOf(_, span)
    | MapOf(_, key_type=_, value_type=_, span)
    | Path(_, _, span)
    | IsNull(_, negated=_, span)
    | IsMissing(_, negated=_, span)
    | Unary(_, _, span)
    | Binary(_, _, _, span)
    | And(_, _, span)
    | Or(_, _, span)
    | Not(_, span)
    | BoolTest(_, _, negated=_, span)
    | Like(_, pattern=_, escape=_, negated=_, span)
    | Between(_, low=_, high=_, negated=_, span)
    | In(_, _, negated=_, span)
    | IsType(_, _, negated=_, span)
    | Case(operand=_, branches=_, default=_, span)
    | Coalesce(_, span)
    | NullIf(_, _, span)
    | Call(_, _, span)
    | Cast(_, _, span)
    | Local(_, span)
    | GlobalOrLocal(_, variable=_, delimited=_, span)
    | Implicit(_, delimited=_, locals=_, span)
    | Select(_, _, distinct=_, span)
    | Subquery(_, _, span)
    | Query(_, order=_, limit=_, offset=_, aliases=_, span)
    | SetOp(_, all=_, outer=_, corresponding=_, _, _, span)
    | With(_, _, span)
    | CollAggregate(_, distinct=_, _, span)
    | Aggregate(_, distinct=_, _, members=_, group=_, span)
    | GlobalsFirst(_, key=_, otherwise=_, span) => span
  }
}

///|
/// Where a relation is in the source.
pub fn Rel::span(self : Rel) -> @ast.Span {
  match self {
    Scan(_, as_=_, at=_, span)
    | Unpivot(_, as_=_, at=_, span)
    | Filter(_, _, span)
    | Join(_, _, _, on=_, span)
    | Let(_, _, span)
    | Group(_, _, group_as=_, members=_, span) => span
  }
}

///|
/// An aggregate function (spec M4c §3.3). SOME is `Any`.
pub(all) enum AggregateKind {
  Count
  Sum
  Avg
  Min
  Max
  Any
  Every
} derive(Debug, Eq)

///|
/// The keys of a GROUP BY (spec M4c §4).
pub(all) enum Grouping {
  /// One group of every binding tuple, also when there are none: GROUP ALL,
  /// or a query with an aggregate or HAVING and no GROUP BY.
  All
  /// The key variables and their expressions.
  By(Array[(String, Expr)])
} derive(Debug)

///|
/// The group variable of a grouped query without GROUP AS. No identifier
/// can name it.
pub let group_variable : String = "\u{0}group"

///|
/// A built-in scalar function (spec M4d1). One argument unless a variant
/// says otherwise.
pub(all) enum Function {
  CharLength
  OctetLength
  BitLength
  Size
  Cardinality
  Exists
  /// Zero or more tuples.
  TupleUnion
  /// [map, key]
  MapGet
  /// [map, key]
  MapContainsKey
  MapKeys
  MapValues
  MapEntries
  Abs
  /// [dividend, divisor]
  Mod
  /// [target] or [characters, target] (source order)
  Trim(@ast.TrimSpec)
  /// [value, start] or [value, start, length]
  Substring
  /// [needle, haystack]
  Position
  /// [value, placing, from] or [value, placing, from, for]
  Overlay
  /// [value, pattern, replacement]
  TextReplace
  Upper
  Lower
  /// The datetime functions (spec M4d3). The field is part of the call.
  Extract(@ast.DatetimeField)
  DateAdd(@ast.DatetimeField)
  DateDiff(@ast.DatetimeField)
  Overlaps
  ToString
  ToTimestamp
  /// The clock functions (spec session-clock §4); the precision is resolved.
  CurrentDate
  CurrentTime(Int32)
  CurrentTimestamp(Int32)
  UtcNow
} derive(Debug, Eq)

///|
/// The SQL name, for messages.
pub fn Function::name(self : Function) -> String {
  match self {
    CharLength => "CHAR_LENGTH"
    OctetLength => "OCTET_LENGTH"
    BitLength => "BIT_LENGTH"
    Size => "SIZE"
    Cardinality => "CARDINALITY"
    Exists => "EXISTS"
    TupleUnion => "TUPLEUNION"
    MapGet => "MAP_GET"
    MapContainsKey => "MAP_CONTAINS_KEY"
    MapKeys => "MAP_KEYS"
    MapValues => "MAP_VALUES"
    MapEntries => "MAP_ENTRIES"
    Abs => "ABS"
    Mod => "MOD"
    Trim(_) => "TRIM"
    Substring => "SUBSTRING"
    Position => "POSITION"
    Overlay => "OVERLAY"
    TextReplace => "TEXT_REPLACE"
    Upper => "UPPER"
    Lower => "LOWER"
    Extract(_) => "EXTRACT"
    DateAdd(_) => "DATE_ADD"
    DateDiff(_) => "DATE_DIFF"
    Overlaps => "OVERLAPS"
    ToString => "TO_STRING"
    ToTimestamp => "TO_TIMESTAMP"
    CurrentDate => "CURRENT_DATE"
    CurrentTime(_) => "CURRENT_TIME"
    CurrentTimestamp(_) => "CURRENT_TIMESTAMP"
    UtcNow => "UTCNOW"
  }
}
