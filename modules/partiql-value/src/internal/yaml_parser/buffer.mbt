///|
// Bounded before growth, including temporary folding and whitespace buffers.
priv struct TextBuffer {
  text : StringBuilder
  mut bytes : Int32
  limit : Int32
  mark : Marker
}

///|
fn TextBuffer::TextBuffer(limit : Int32, mark : Marker) -> TextBuffer {
  { text: StringBuilder(), bytes: 0, limit, mark, }
}

///|
fn utf8_size(c : Char) -> Int32 {
  let n = c.to_int()
  if n <= 0x7f {
    1
  } else if n <= 0x7ff {
    2
  } else if n <= 0xffff {
    3
  } else {
    4
  }
}

///|
fn TextBuffer::write_char(self : TextBuffer, c : Char) -> Unit raise YamlError {
  let count = utf8_size(c)
  if count > self.limit - self.bytes {
    raise ResourceLimit(
      mark=self.mark,
      info="scalar payload exceeds the UTF-8 byte budget",
    )
  }
  self.bytes += count
  self.text.write_char(c)
}

///|
fn TextBuffer::write_stringview(
  self : TextBuffer,
  s : StringView,
) -> Unit raise YamlError {
  for c in s {
    self.write_char(c)
  }
}

///|
fn TextBuffer::write_string(
  self : TextBuffer,
  s : String,
) -> Unit raise YamlError {
  self.write_stringview(s)
}

///|
fn TextBuffer::to_string(self : TextBuffer) -> String {
  self.text.to_string()
}

///|
fn TextBuffer::is_empty(self : TextBuffer) -> Bool {
  self.bytes == 0
}

///|
fn TextBuffer::reset(self : TextBuffer) -> Unit {
  self.bytes = 0
  self.text.reset()
}
