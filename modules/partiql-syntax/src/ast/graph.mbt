// Graph pattern matching (GPML): RFC 0033 and the Kotlin gpml rules. The
// parser guarantees the invariants in the doc comments (spec M2b section 5).

///|
/// `(graph MATCH pattern)`, or `graph MATCH pattern` as a FROM item. The
/// span includes the parentheses of the parenthesized form.
#derive(Debug, Eq)
pub(all) struct GraphMatch {
  graph : Expr
  pattern : GraphPattern
  span : Span
}

///|
/// A selector, one or more path patterns, and an optional postfilter.
/// `paths` is never empty; `where_` is `None` in the FROM form.
#derive(Debug, Eq)
pub(all) struct GraphPattern {
  selector : Selector?
  paths : Array[PathPattern]
  where_ : Expr?
  span : Span
}

///|
/// A graph path selector and the span of its selector keywords and count.
#derive(Debug, Eq)
pub(all) struct Selector {
  kind : SelectorKind
  span : Span
}

///|
/// Counts are not negative.
#derive(Debug, Eq)
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
}

///|
/// The path repetition rule: WALK permits repeats, TRAIL forbids repeated
/// edges, ACYCLIC forbids repeated nodes, and SIMPLE permits only the
/// starting node to repeat as the ending node.
#derive(Debug, Eq)
pub(all) enum Restrictor {
  Walk
  Trail
  Acyclic
  Simple
}

///|
/// `[restrictor] [name =] part+`. `parts` is never empty.
#derive(Debug, Eq)
pub(all) struct PathPattern {
  restrictor : Restrictor?
  variable : Identifier?
  parts : Array[PathPart]
  span : Span
}

///|
/// One node, edge or nested group in a graph path, in traversal order.
#derive(Debug, Eq)
pub(all) enum PathPart {
  Node(NodePattern)
  Edge(EdgePattern)
  Group(GroupPattern)
}

///|
/// `( [name] [: label] [WHERE expr] )`
#derive(Debug, Eq)
pub(all) struct NodePattern {
  variable : Identifier?
  label : Label?
  where_ : Expr?
  span : Span
}

///|
/// An edge. `filler` is `None` only for the abbreviated form (`->`), so
/// `->` and `-[]->` stay different. The span includes the quantifier.
#derive(Debug, Eq)
pub(all) struct EdgePattern {
  direction : EdgeDirection
  filler : EdgeFiller?
  quantifier : Quantifier?
  span : Span
}

///|
/// `[ [name] [: label] [WHERE expr] ]`
#derive(Debug, Eq)
pub(all) struct EdgeFiller {
  variable : Identifier?
  label : Label?
  where_ : Expr?
  span : Span
}

///|
/// The allowed edge directions, retaining abbreviated and mixed-direction
/// syntax through the surrounding `EdgePattern`.
#derive(Debug, Eq)
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
}

///|
/// `( path [WHERE expr] )` or `[ path [WHERE expr] ]`, with an optional
/// quantifier. The span includes the quantifier.
#derive(Debug, Eq)
pub(all) struct GroupPattern {
  delimiter : GroupDelimiter
  path : PathPattern
  where_ : Expr?
  quantifier : Quantifier?
  span : Span
}

///|
/// Whether a graph path group was enclosed in parentheses or brackets.
#derive(Debug, Eq)
pub(all) enum GroupDelimiter {
  Paren
  Bracket
}

///|
/// A graph path repetition bound and its complete source span.
#derive(Debug, Eq)
pub(all) struct Quantifier {
  kind : QuantifierKind
  span : Span
}

///|
/// Bounds are not negative, and `upper >= lower`.
#derive(Debug, Eq)
pub(all) enum QuantifierKind {
  /// `+`
  Plus
  /// `*`
  Star
  /// `{lower,upper}` or `{lower,}`
  Range(lower~ : Int32, upper~ : Int32?)
}

///|
/// A label expression. The span of a parenthesized label includes the
/// parentheses.
#derive(Debug, Eq)
pub(all) struct Label {
  kind : LabelKind
  span : Span
}

///|
/// A graph label name, wildcard, negation, conjunction or disjunction.
#derive(Debug, Eq)
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
}
