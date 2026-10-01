///|
/// Skips an Ion string or quoted symbol that starts at the cursor: `"..."`
/// or `'...'` with backslash escapes, or a `'''...'''` long string.
fn Scanner::skip_ion_quoted(
  self : Scanner,
  start : Int,
) -> Unit raise @ast.ParseError {
  let q = self.at(0)
  if q == '\''.to_int() && self.at(1) == q && self.at(2) == q {
    self.pos += 3
    while !(self.at(0) == q && self.at(1) == q && self.at(2) == q) {
      if self.at(0) == -1 {
        raise error("unterminated Ion literal", start, self.pos)
      }
      // An escape skips the next unit, but never past the end.
      if self.at(0) == '\\'.to_int() && self.at(1) != -1 {
        self.pos += 1
      }
      self.pos += 1
    }
    self.pos += 3
    return
  }
  self.pos += 1
  while self.at(0) != q {
    if self.at(0) == -1 {
      raise error("unterminated Ion literal", start, self.pos)
    }
    // An escape skips the next unit, but never past the end.
    if self.at(0) == '\\'.to_int() && self.at(1) != -1 {
      self.pos += 1
    }
    self.pos += 1
  }
  self.pos += 1
}

///|
/// An Ion literal: scans to the closing backtick, skipping Ion strings,
/// quoted symbols and comments (which may hold a backtick), then checks the
/// body with the Ion text reader.
fn ion_literal(s : Scanner) -> TokenKind raise @ast.ParseError {
  let start = s.pos
  s.pos += 1
  let body_start = s.pos
  while s.at(0) != '`'.to_int() {
    let c = s.at(0)
    if c == -1 {
      raise error("unterminated Ion literal", start, s.pos)
    } else if c == '{'.to_int() && s.at(1) == '{'.to_int() {
      // A blob or clob: base64 may contain `//`, and a clob holds a string.
      s.pos += 2
      while !(s.at(0) == '}'.to_int() && s.at(1) == '}'.to_int()) {
        if s.at(0) == -1 {
          raise error("unterminated Ion literal", start, s.pos)
        } else if s.at(0) == '"'.to_int() || s.at(0) == '\''.to_int() {
          s.skip_ion_quoted(start)
        } else {
          s.pos += 1
        }
      }
      s.pos += 2
    } else if c == '"'.to_int() || c == '\''.to_int() {
      s.skip_ion_quoted(start)
    } else if c == '/'.to_int() && s.at(1) == '/'.to_int() {
      while s.at(0) != -1 && s.at(0) != '\n'.to_int() {
        s.pos += 1
      }
    } else if c == '/'.to_int() && s.at(1) == '*'.to_int() {
      s.pos += 2
      while !(s.at(0) == '*'.to_int() && s.at(1) == '/'.to_int()) {
        if s.at(0) == -1 {
          raise error("unterminated Ion literal", start, s.pos)
        }
        s.pos += 1
      }
      s.pos += 2
    } else {
      s.pos += 1
    }
  }
  let body = s.text(body_start, s.pos)
  s.pos += 1
  let value = @text.read_ion(body) catch {
    e =>
      raise @ast.ParseError::Syntax(
        message="invalid Ion literal: \{@debug.to_string(e)}",
        span={ start, end: s.pos, },
        expected=[],
        found="Ion literal",
      )
  }
  IonLit(body, value)
}
