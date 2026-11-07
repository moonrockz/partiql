///|
/// Whether a preserved source comment uses line or block delimiters.
#derive(Debug, Eq)
pub(all) enum CommentKind {
  /// `-- …` up to the end of the line
  Line
  /// `/* … */`
  Block
}

///|
/// A comment as written: `-- note` (without the line break) or `/* note */`.
#derive(Debug, Eq)
pub(all) struct Comment {
  kind : CommentKind
  text : String
  span : Span
}

///|
/// The statements of a script, and the comments of its source in source order.
#derive(Debug, Eq)
pub(all) struct Script {
  statements : Array[Statement]
  comments : Array[Comment]
  span : Span
}

///|
/// The result of `parse_script_recovering`: the partial script and every
/// error, in source order (spec M3d §3).
#derive(Debug, Eq)
pub(all) struct Recovered {
  script : Script
  errors : Array[ParseError]
}
