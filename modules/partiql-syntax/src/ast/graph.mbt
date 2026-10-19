// Graph pattern matching (GPML): RFC 0033 and the Kotlin gpml rules. The
// parser guarantees the invariants in the doc comments (spec M2b section 5).

///|
/// `(graph MATCH pattern)`, or `graph MATCH pattern` as a FROM item. The
/// span includes the parentheses of the parenthesized form.
pub(all) struct GraphMatch {
  graph : Expr
  pattern : GraphPattern
  span : Span
} derive(Debug, Eq)

///|
/// A selector, one or more path patterns, and an optional postfilter.
/// `paths` is never empty; `where_` is `None` in the FROM form.
pub(all) struct GraphPattern {
  selector : Selector?
  paths : Array[PathPattern]
  where_ : Expr?
  span : Span
} derive(Debug, Eq)

///|
/// A graph path selector and the span of its selector keywords and count.
pub(all) struct Selector {
  kind : SelectorKind
  span : Span
} derive(Debug, Eq)

///|
/// Counts are not negative.
pub(all) enum SelectorKind {
  /// `ANY SHORTEST`
  AnyShortest
  /// `ALL SHORTEST`
  AllShortest
  /// `SHORTEST`
  Shortest
  /// `ANY [k]`
  Any(k~ : Int32?)
  /// `SHORTEST k [GROUP]`
  ShortestK(k~ : Int32, group~ : Bool)
} derive(Debug, Eq)

///|
/// The path repetition rule: WALK permits repeats, TRAIL forbids repeated
/// edges, ACYCLIC forbids repeated nodes, and SIMPLE permits only the
/// starting node to repeat as the ending node.
pub(all) enum Restrictor {
  Walk
  Trail
  Acyclic
  Simple
} derive(Debug, Eq)

///|
/// `[restrictor] [name =] part+`. `parts` is never empty.
pub(all) struct PathPattern {
  restrictor : Restrictor?
  variable : Identifier?
  parts : Array[PathPart]
  span : Span
} derive(Debug, Eq)

///|
/// One node, edge or nested group in a graph path, in traversal order.
pub(all) enum PathPart {
  Node(NodePattern)
  Edge(EdgePattern)
  Group(GroupPattern)
} derive(Debug, Eq)

///|
/// `( [name] [: label] [WHERE expr] )`
pub(all) struct NodePattern {
  variable : Identifier?
  label : Label?
  where_ : Expr?
  span : Span
} derive(Debug, Eq)

///|
/// An edge. `filler` is `None` only for the abbreviated form (`->`), so
/// `->` and `-[]->` stay different. The span includes the quantifier.
pub(all) struct EdgePattern {
  direction : EdgeDirection
  filler : EdgeFiller?
  quantifier : Quantifier?
  span : Span
} derive(Debug, Eq)

///|
/// `[ [name] [: label] [WHERE expr] ]`
pub(all) struct EdgeFiller {
  variable : Identifier?
  label : Label?
  where_ : Expr?
  span : Span
} derive(Debug, Eq)

///|
/// The allowed edge directions, retaining abbreviated and mixed-direction
/// syntax through the surrounding `EdgePattern`.
pub(all) enum EdgeDirection {
  /// `<-[ ]-`, `<-`
  Left
  /// `~[ ]~`, `~`
  Undirected
  /// `-[ ]->`, `->`
  Right
  /// `<~[ ]~`, `<~`
  LeftOrUndirected
  /// `~[ ]~>`, `~>`
  UndirectedOrRight
  /// `<-[ ]->`, `<->`
  LeftOrRight
  /// `-[ ]-`, `-`
  Any
} derive(Debug, Eq)

///|
/// `( path [WHERE expr] )` or `[ path [WHERE expr] ]`, with an optional
/// quantifier. The span includes the quantifier.
pub(all) struct GroupPattern {
  delimiter : GroupDelimiter
  path : PathPattern
  where_ : Expr?
  quantifier : Quantifier?
  span : Span
} derive(Debug, Eq)

///|
/// Whether a graph path group was enclosed in parentheses or brackets.
pub(all) enum GroupDelimiter {
  Paren
  Bracket
} derive(Debug, Eq)

///|
/// A graph path repetition bound and its complete source span.
pub(all) struct Quantifier {
  kind : QuantifierKind
  span : Span
} derive(Debug, Eq)

///|
/// Bounds are not negative, and `upper >= lower`.
pub(all) enum QuantifierKind {
  /// `+`
  Plus
  /// `*`
  Star
  /// `{lower,upper}` or `{lower,}`
  Range(lower~ : Int32, upper~ : Int32?)
} derive(Debug, Eq)

///|
/// A label expression. The span of a parenthesized label includes the
/// parentheses.
pub(all) struct Label {
  kind : LabelKind
  span : Span
} derive(Debug, Eq)

///|
/// A graph label name, wildcard, negation, conjunction or disjunction.
pub(all) enum LabelKind {
  Name(Identifier)
  /// `%`
  Wildcard
  /// `!label`
  Not(Label)
  /// `label & label`
  And(Label, Label)
  /// `label | label`
  Or(Label, Label)
} derive(Debug, Eq)
