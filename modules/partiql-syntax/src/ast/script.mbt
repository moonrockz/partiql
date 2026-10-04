///|
pub(all) enum CommentKind {
  /// `-- …` up to the end of the line
  Line
  /// `/* … */`
  Block
} derive(Debug, Eq)

///|
/// A comment as written: `-- note` (without the line break) or `/* note */`.
pub(all) struct Comment {
  kind : CommentKind
  text : String
  span : Span
} derive(Debug, Eq)

///|
/// The statements of a script, and the comments of its source in source order.
pub(all) struct Script {
  statements : Array[Statement]
  comments : Array[Comment]
  span : Span
} derive(Debug, Eq)

///|
/// The result of `parse_script_recovering`: the partial script and every
/// error, in source order (spec M3d §3).
pub(all) struct Recovered {
  script : Script
  errors : Array[ParseError]
} derive(Debug, Eq)
