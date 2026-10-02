///|
/// A 1-based line and a 1-based column counted in code points.
pub(all) struct Position {
  line : Int
  column : Int
} derive(Debug, Eq)

///|
fn is_high_surrogate(c : Int) -> Bool {
  c >= 0xD800 && c <= 0xDBFF
}

///|
/// The position of UTF-16 `offset` in `source`. `\r\n` ends one line.
pub fn position(source : String, offset : Int) -> Position {
  let end = if offset < source.length() { offset } else { source.length() }
  let mut line = 1
  let mut column = 1
  let mut i = 0
  while i < end {
    let c = source.at(i).to_int()
    if c == '\n'.to_int() {
      line += 1
      column = 1
      i += 1
    } else if c == '\r'.to_int() &&
      i + 1 < source.length() &&
      source.at(i + 1).to_int() == '\n'.to_int() {
      i += 1
    } else {
      column += 1
      i += if is_high_surrogate(c) && i + 1 < end { 2 } else { 1 }
    }
  }
  { line, column, }
}

///|
/// The text of 1-based `line`, without its line break.
fn line_text(source : String, line : Int) -> String {
  let lines = source.split("\n").map(v => v.to_owned()).collect()
  if line - 1 < lines.length() {
    let text = lines[line - 1]
    if text.has_suffix("\r") {
      text.view(end_offset=text.length() - 1).to_owned()
    } else {
      text
    }
  } else {
    ""
  }
}
