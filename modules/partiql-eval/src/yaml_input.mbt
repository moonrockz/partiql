///|
fn bindings_from_yaml(
  values : Array[@value.Value],
) -> Bindings raise @partiql_yaml.YamlError {
  match values {
    [Tuple(t)] => Bindings::of_tuple(t)
    _ =>
      raise @partiql_yaml.YamlError::YamlError(
        kind=Bindings,
        location=None,
        message="bindings need exactly one YAML mapping document",
      )
  }
}

///|
/// Decode one YAML mapping into globals, preserving exact finite numbers.
pub fn Bindings::from_yaml_text(
  source : StringView,
) -> Bindings raise @partiql_yaml.YamlError {
  bindings_from_yaml(@partiql_yaml.read_text(source))
}

///|
/// Decode one UTF-8 YAML mapping into globals.
pub fn Bindings::from_yaml_bytes(
  source : BytesView,
) -> Bindings raise @partiql_yaml.YamlError {
  bindings_from_yaml(@partiql_yaml.read_bytes(source))
}
