///|
pub suberror YamlError {
  /// - `mark`: The position at which the error happened in the source.
  /// - `info`: Human-readable details about the error.
  UnsupportedVersion(mark~ : Marker)
  ResourceLimit(mark~ : Marker, info~ : String)
  YamlError(mark~ : Marker, info~ : String)
} derive(Debug)

///|
pub extend YamlError with @moonbitlang/core/debug.Debug::{to_repr}
