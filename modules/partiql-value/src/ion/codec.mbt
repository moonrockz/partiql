///|
/// An Ion value that has no PartiQL meaning in this version of the codec.
pub(all) suberror CodecError {
  Unsupported(String)
} derive(Debug, Eq)

///|
let missing_annotation = "$missing"

///|
/// Decodes a value in the PartiQL-encoded Ion form that `partiql-tests`
/// uses (`$missing::null` for MISSING, `null` for NULL).
pub fn from_ion(value : @ion_core.IonValue) -> @value.Value raise CodecError {
  let annotations = value.annotations()
  match (value.kind(), annotations.length()) {
    (Null(Null), 0) => @value.Value::Null
    (Null(Null), 1) if annotations[0].text() == Some(missing_annotation) =>
      @value.Value::Missing
    _ =>
      raise CodecError::Unsupported(
        "\{@debug.to_string(value.ion_type())} value",
      )
  }
}

///|
/// Encodes a value in the PartiQL-encoded Ion form.
pub fn to_ion(value : @value.Value) -> @ion_core.IonValue {
  match value {
    Null => @ion_core.IonValue::untyped_null()
    Missing =>
      @ion_core.IonValue::untyped_null().with_annotation(
        @ion_core.SymbolToken::new(missing_annotation),
      )
    // Temporary until M1 task 8 rewrites the codec.
    _ => abort("to_ion: not implemented for this value yet")
  }
}
