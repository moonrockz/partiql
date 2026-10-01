///|
/// Why a statement could not be parsed.
pub(all) suberror ParseError {
  /// Valid PartiQL that this version does not parse yet. Reserved for later
  /// milestones; nothing raises it since M2b.
  Unsupported(message~ : String, span~ : Span)
  /// Not valid PartiQL. `expected` lists what the parser could accept at
  /// `span`; `found` describes what it found there.
  Syntax(
    message~ : String,
    span~ : Span,
    expected~ : Array[String],
    found~ : String
  )
} derive(Debug, Eq)
