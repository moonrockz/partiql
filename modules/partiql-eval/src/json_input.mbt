///|
fn bindings_from_json(
  value : @value.Value,
) -> Bindings raise @partiql_json.JsonError {
  match value {
    Tuple(t) => Bindings::of_tuple(t)
    _ =>
      raise @partiql_json.JsonError::Bindings("bindings need one JSON object")
  }
}

///|
/// Decode one strict JSON object into global bindings, preserving exact numbers.
pub fn Bindings::from_json_text(
  source : StringView,
) -> Bindings raise @partiql_json.JsonError {
  bindings_from_json(@partiql_json.read_text(source))
}

///|
/// Decode one UTF-8 JSON object into global bindings.
pub fn Bindings::from_json_bytes(
  source : BytesView,
) -> Bindings raise @partiql_json.JsonError {
  bindings_from_json(@partiql_json.read_bytes(source))
}
