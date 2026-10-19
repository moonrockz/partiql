///|
/// Errors at the JSON boundary. Syntax offsets count UTF-16 code units from
/// the start of the document. Unsupported values are never replaced by null.
pub(all) suberror JsonError {
  Utf8
  Syntax(offset~ : Int32, message~ : String)
  Unsupported(String)
  Bindings(String)
} derive(Debug)

///|
pub fn JsonError::message(self : JsonError) -> String {
  match self {
    Utf8 => "JSON text is not valid UTF-8"
    Syntax(offset~, message~) => "JSON at offset \{offset}: \{message}"
    Unsupported(message) => "cannot represent as JSON: " + message
    Bindings(message) => message
  }
}

///|
priv struct Reader {
  source : StringView
  mut pos : Int32
}

///|
fn Reader::error(self : Reader, message : String) -> JsonError {
  Syntax(offset=self.pos, message~)
}

///|
fn Reader::skip_space(self : Reader) -> Unit {
  while self.pos < self.source.length() {
    match self.source[self.pos] {
      ' ' | '\t' | '\r' | '\n' => self.pos += 1
      _ => break
    }
  }
}

///|
fn Reader::take(self : Reader, char : UInt16) -> Bool {
  self.skip_space()
  if self.pos < self.source.length() && self.source[self.pos] == char {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Reader::string(self : Reader) -> String raise JsonError {
  self.skip_space()
  let start = self.pos
  if !self.take('"') {
    raise self.error("expected a quoted object key")
  }
  while self.pos < self.source.length() {
    let c = self.source[self.pos]
    self.pos += 1
    if c == '"' {
      let token = self.source[start:self.pos]
      let json = @core_json.parse(token) catch {
        e => raise Syntax(offset=start, message=e.to_string())
      }
      match json {
        String(s) => return s
        _ => raise self.error("expected a string")
      }
    }
    if c == '\\' && self.pos < self.source.length() {
      self.pos += 1
    }
  }
  raise self.error("unterminated string")
}

///|
fn Reader::value(self : Reader, depth : Int32) -> @value.Value raise JsonError {
  self.skip_space()
  guard self.pos < self.source.length() else {
    raise self.error("expected a JSON value")
  }
  match self.source[self.pos] {
    '"' => @value.Value::from_string(self.string())
    '[' => {
      if depth >= 256 {
        raise self.error("nesting exceeds 256 containers")
      }
      self.pos += 1
      let items : Array[@value.Value] = []
      if self.take(']') {
        return @value.Value::from_list(items)
      }
      while true {
        items.push(self.value(depth + 1))
        if self.take(']') {
          break
        }
        if !self.take(',') {
          raise self.error("expected ',' or ']'")
        }
      }
      @value.Value::from_list(items)
    }
    '{' => {
      if depth >= 256 {
        raise self.error("nesting exceeds 256 containers")
      }
      self.pos += 1
      let fields : Array[(String, @value.Value)] = []
      if self.take('}') {
        return @value.Value::from_tuple(@value.Tuple(fields))
      }
      while true {
        let name = self.string()
        if !self.take(':') {
          raise self.error("expected ':'")
        }
        fields.push((name, self.value(depth + 1)))
        if self.take('}') {
          break
        }
        if !self.take(',') {
          raise self.error("expected ',' or '}'")
        }
      }
      @value.Value::from_tuple(@value.Tuple(fields))
    }
    _ => self.scalar()
  }
}

///|
// Validate scalar syntax with the base library, but decode number spelling
// ourselves: Json's Double payload cannot retain decimal precision or scale.
fn Reader::scalar(self : Reader) -> @value.Value raise JsonError {
  let start = self.pos
  while self.pos < self.source.length() {
    match self.source[self.pos] {
      ' ' | '\t' | '\r' | '\n' | ',' | ']' | '}' => break
      _ => self.pos += 1
    }
  }
  let token = self.source[start:self.pos]
  let json = @core_json.parse(token) catch {
    e => raise Syntax(offset=start, message=e.to_string())
  }
  match json {
    Null => Null
    True => @value.Value::from_bool(true)
    False => @value.Value::from_bool(false)
    Number(_) => {
      let spelling = token.to_owned()
      if spelling.contains(".") ||
        spelling.contains("e") ||
        spelling.contains("E") {
        let decimal = @ion_core.Decimal::parse(
          spelling.replace(old="e", new="d").replace(old="E", new="d"),
        ) catch {
          e => raise Syntax(offset=start, message=e.message())
        }
        @value.Value::from_decimal(decimal)
      } else {
        @value.Value::from_bigint(@bigint.BigInt::from_string(spelling))
      }
    }
    _ => raise Syntax(offset=start, message="expected a JSON scalar")
  }
}

///|
/// Read exactly one strict JSON document. Integers normalize to Int/BigInt;
/// fractions and exponents become exact Decimal values. Duplicate keys survive.
/// Strings must contain Unicode scalar values; unpaired surrogates are errors.
/// At most 256 nested containers and Int32 decimal exponents are supported.
pub fn read_text(source : StringView) -> @value.Value raise JsonError {
  let reader = Reader::{ source, pos: 0, }
  let value = reader.value(0)
  reader.skip_space()
  if reader.pos != source.length() {
    raise reader.error("unexpected trailing input; expected one JSON document")
  }
  value
}

///|
/// Read one strict UTF-8 JSON document. A BOM is not accepted.
pub fn read_bytes(source : BytesView) -> @value.Value raise JsonError {
  let text = @utf8.decode(source) catch { _ => raise Utf8 }
  read_text(text)
}
