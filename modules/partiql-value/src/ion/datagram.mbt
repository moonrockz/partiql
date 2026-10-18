///|
/// Errors at the Ion transport boundary. Codec errors retain their distinction
/// between malformed and unsupported PartiQL encodings.
pub(all) suberror IonDataError {
  Utf8
  Text(@ion_core.IonError)
  Binary(@ion_core.IonError)
  Codec(CodecError)
  Schema(@ion_core.IonError)
  Violations(Array[ValidationViolation])
  Write(@ion_core.IonError)
  Bindings(String)
} derive(Debug)

///|
pub fn IonDataError::message(self : IonDataError) -> String {
  match self {
    Utf8 => "Ion text is not valid UTF-8"
    Text(e) => "Ion text: " + e.message()
    Binary(e) => "binary Ion: " + e.message()
    Codec(Unsupported(s)) => "unsupported PartiQL encoding: " + s
    Codec(Malformed(s)) => "malformed PartiQL encoding: " + s
    Schema(e) => "Ion Schema: " + e.message()
    Violations(vs) =>
      vs.map(v => "Ion Schema: " + v.path + ": " + v.message).join("\n")
    Write(e) => "cannot write Ion: " + e.message()
    Bindings(s) => s
  }
}

///|
/// A schema violation with its location in the input datagram.
pub struct ValidationViolation {
  path : String
  message : String
} derive(Debug)

///|
/// A schema applied to raw Ion, before PartiQL decoding.
pub struct Validation {
  priv schema : @schema.Schema
  priv type_name : String
  priv document : Bool
}

///|
/// Validate every element and collect violations from all elements.
pub fn Validation::elements(
  schema : @schema.Schema,
  type_name : String,
) -> Validation {
  { schema, type_name, document: false, }
}

///|
/// Validate a whole datagram using an Ion Schema document type.
pub fn Validation::document(
  schema : @schema.Schema,
  type_name : String,
) -> Validation {
  { schema, type_name, document: true, }
}

///|
fn Validation::check(
  self : Validation,
  values : Array[@ion_core.IonValue],
) -> Unit raise IonDataError {
  let violations = try {
    if self.document {
      self.schema
      .validate_document(self.type_name, values)
      .map(v => ValidationViolation::{ path: v.path, message: v.message, })
    } else {
      let all : Array[ValidationViolation] = []
      // Check the type even for an empty datagram.
      if self.schema.find(self.type_name) is None {
        raise @ion_core.IonError::DataModel(
          "unknown schema type: " + self.type_name,
        )
      }
      for i, value in values {
        for v in self.schema.validate(self.type_name, value) {
          all.push({
            path: "$[\{i}]" + v.path[1:].to_owned(),
            message: v.message,
          })
        }
      }
      all
    }
  } catch {
    e => raise Schema(e)
  }
  if !violations.is_empty() {
    raise Violations(violations)
  }
}

///|
fn decode_datagram(
  values : Array[@ion_core.IonValue],
  validation : Validation?,
) -> Array[@value.Value] raise IonDataError {
  if validation is Some(v) {
    v.check(values)
  }
  values.map(v => from_ion(v) catch { e => raise Codec(e) })
}

///|
/// Read a full PartiQL-encoded Ion text datagram. No implicit bag conversion.
pub fn read_text(
  source : StringView,
  catalog? : @ion_core.Catalog,
  validation? : Validation,
) -> Array[@value.Value] raise IonDataError {
  let ions = @text.read_ion_datagram(source, catalog?) catch {
    e => raise Text(e)
  }
  decode_datagram(ions, validation)
}

///|
/// Detect binary Ion by its version marker, otherwise read strict UTF-8 text.
pub fn read_bytes(
  source : BytesView,
  catalog? : @ion_core.Catalog,
  validation? : Validation,
) -> Array[@value.Value] raise IonDataError {
  decode_datagram(read_ions_bytes(source, catalog?), validation)
}

///|
fn read_ions_bytes(
  source : BytesView,
  catalog? : @ion_core.Catalog,
) -> Array[@ion_core.IonValue] raise IonDataError {
  if @binary.has_binary_version_marker(source) {
    @binary.read_binary(source, catalog?) catch {
      e => raise Binary(e)
    }
  } else {
    let text = @utf8.decode(source) catch { _ => raise Utf8 }
    @text.read_ion_datagram(text, catalog?) catch {
      e => raise Text(e)
    }
  }
}

///|
/// Load an Ion Schema from binary or UTF-8 text. Imports can be resolved by
/// the supplied resolver, just as in the upstream schema loader.
pub fn load_schema_bytes(
  source : BytesView,
  resolver? : (String) -> Array[@ion_core.IonValue] raise @ion_core.IonError,
) -> @schema.Schema raise IonDataError {
  let ions = read_ions_bytes(source)
  @schema.Schema::load(ions, resolver?) catch {
    e => raise Schema(e)
  }
}

///|
/// Write a binary datagram with one local symbol table. Unresolved shared
/// symbols retain their import metadata.
pub fn write_bytes(values : Array[@value.Value]) -> Bytes raise IonDataError {
  @binary.write_binary(values.map(to_ion)) catch {
    e => raise Write(e)
  }
}

///|
/// Write one Ion value per line, with a final newline for nonempty datagrams.
pub fn write_text(
  values : Array[@value.Value],
  pretty~ : Bool = false,
) -> String raise IonDataError {
  let out = StringBuilder()
  for value in values {
    let ion = to_ion(value)
    let text = try {
      if pretty {
        @text.write_ion_pretty(ion)
      } else {
        @text.write_ion(ion)
      }
    } catch {
      e => raise Write(e)
    }
    out.write_string(text)
    out.write_char('\n')
  }
  out.to_string()
}
