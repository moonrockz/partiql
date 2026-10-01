///|
/// Why an Ion value could not be decoded.
pub(all) suberror CodecError {
  /// A valid PartiQL-encoded form that this version does not support.
  Unsupported(String)
  /// Not a valid PartiQL-encoded value.
  Malformed(String)
} derive(Debug, Eq)
