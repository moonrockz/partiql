///|
fn newline(out : StringBuilder, pretty : Bool, depth : Int32) -> Unit {
  if pretty {
    out.write_char('\n')
    out.write_string("  ".repeat(depth))
  }
}

///|
fn write_value(
  out : StringBuilder,
  value : @value.Value,
  pretty : Bool,
  depth : Int32,
) -> Unit raise JsonError {
  match value {
    Null => out.write_string("null")
    Bool(b) => out.write_string(if b { "true" } else { "false" })
    Int(n) => out.write_string(n.to_string())
    BigInt(n) => out.write_string(n.to_string())
    Decimal(d) => {
      // Always retain an exponent, even zero, to preserve Decimal vs Int and
      // the exact coefficient, scale and sign of zero on read-back.
      if d.is_negative_zero() {
        out.write_char('-')
      }
      out.write_string(d.coefficient().to_string())
      out.write_char('e')
      out.write_string(d.exponent().to_string())
    }
    Float(f) => {
      if f.is_nan() || f.is_inf() {
        raise Unsupported("non-finite Float")
      }
      // Core Json.stringify normalizes negative zero to 0.
      out.write_string(
        if f == 0.0 && f.reinterpret_as_int64() < 0L {
          "-0.0"
        } else {
          Json::number(f).stringify()
        },
      )
    }
    String(s) => out.write_string(Json::string(s).stringify())
    List(items) => {
      if depth >= 256 {
        raise Unsupported("nesting exceeds 256 containers")
      }
      out.write_char('[')
      for i, item in items {
        if i > 0 {
          out.write_char(',')
        }
        newline(out, pretty, depth + 1)
        write_value(out, item, pretty, depth + 1)
      }
      if !items.is_empty() {
        newline(out, pretty, depth)
      }
      out.write_char(']')
    }
    Tuple(t) => {
      if depth >= 256 {
        raise Unsupported("nesting exceeds 256 containers")
      }
      out.write_char('{')
      let fields = t.fields()
      for i, field in fields {
        if i > 0 {
          out.write_char(',')
        }
        newline(out, pretty, depth + 1)
        out.write_string(Json::string(field.0).stringify())
        out.write_char(':')
        if pretty {
          out.write_char(' ')
        }
        write_value(out, field.1, pretty, depth + 1)
      }
      if !fields.is_empty() {
        newline(out, pretty, depth)
      }
      out.write_char('}')
    }
    Missing => raise Unsupported("Missing")
    Bag(_) =>
      raise Unsupported("Bag; explicitly convert the query result to a list")
    Map(_) => raise Unsupported("Map")
    Graph(_) => raise Unsupported("Graph")
    Date(_) => raise Unsupported("Date")
    Time(_) => raise Unsupported("Time")
    Timestamp(_) => raise Unsupported("Timestamp")
    IntervalYM(_) => raise Unsupported("IntervalYM")
    IntervalDT(_) => raise Unsupported("IntervalDT")
    Blob(_) => raise Unsupported("Blob")
    Clob(_) => raise Unsupported("Clob")
    Ion(_) => raise Unsupported("boxed Ion")
  }
}

///|
/// Write one JSON document, without a trailing newline. Duplicate tuple fields
/// are emitted in order. Decimals retain their scale. Finite floats use the
/// shortest round-trippable binary64 spelling; reading it gives Int/Decimal,
/// not Float. Other PartiQL types and non-finite floats raise Unsupported.
/// At most 256 nested containers are supported, matching read_text.
pub fn write_text(
  value : @value.Value,
  pretty~ : Bool = false,
) -> String raise JsonError {
  let out = StringBuilder()
  write_value(out, value, pretty, 0)
  out.to_string()
}

///|
/// Write one JSON document as UTF-8, without a BOM or trailing newline.
pub fn write_bytes(
  value : @value.Value,
  pretty~ : Bool = false,
) -> Bytes raise JsonError {
  @utf8.encode(write_text(value, pretty~))
}
