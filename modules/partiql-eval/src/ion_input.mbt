///|
fn bindings_from_values(
  values : Array[@value.Value],
) -> Bindings raise @partiql_ion.IonDataError {
  match values {
    [Tuple(t)] => Bindings::of_tuple(t)
    _ =>
      raise @partiql_ion.IonDataError::Bindings("bindings need one Ion struct")
  }
}

///|
/// Decode exactly one environment struct. Catalog and validation apply to raw Ion.
pub fn Bindings::from_ion_text(
  source : StringView,
  catalog? : @ion_core.Catalog,
  validation? : @partiql_ion.Validation,
) -> Bindings raise @partiql_ion.IonDataError {
  bindings_from_values(@partiql_ion.read_text(source, catalog?, validation?))
}

///|
/// Decode a binary or UTF-8 text environment, detected from the version marker.
pub fn Bindings::from_ion_bytes(
  source : BytesView,
  catalog? : @ion_core.Catalog,
  validation? : @partiql_ion.Validation,
) -> Bindings raise @partiql_ion.IonDataError {
  bindings_from_values(@partiql_ion.read_bytes(source, catalog?, validation?))
}

///|
/// Return bindings with `name` replaced or appended. The input array is copied.
pub fn Bindings::with_value(
  self : Bindings,
  name : String,
  value : @value.Value,
) -> Bindings {
  let entries = self.entries.filter(e => e.0 != name)
  entries.push((name, value))
  Bindings::of_pairs(entries)
}

///|
/// Bind a whole datagram: zero elements form an empty bag, one is used as-is,
/// and many form a bag. Use Session::evaluate_each for individual documents.
pub fn Bindings::with_data(
  self : Bindings,
  name : String,
  values : Array[@value.Value],
) -> Bindings {
  let value : @value.Value = match values {
    [v] => v
    _ => Bag(@value.Bag::Bag(values.copy()))
  }
  self.with_value(name, value)
}
