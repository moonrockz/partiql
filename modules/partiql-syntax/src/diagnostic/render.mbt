// rustc-style rendering of a ParseError (spec M3c section 5).

///|
let red : String = "\u{1b}[1;31m"

///|
let blue : String = "\u{1b}[1;34m"

///|
let bold : String = "\u{1b}[1m"

///|
let reset : String = "\u{1b}[0m"

///|
fn paint(text : String, style : String, color : Bool) -> String {
  if color && text != "" {
    style + text + reset
  } else {
    text
  }
}

///|
/// `a, b or c`
fn or_list(items : Array[String]) -> String {
  match items.length() {
    0 => ""
    1 => items[0]
    n => items[:n - 1].to_owned().join(", ") + " or " + items[n - 1]
  }
}

///|
/// Expands tabs to 4 spaces.
fn expand(text : String) -> String {
  let buf = StringBuilder()
  for c in text {
    match c {
      '\t' => buf.write_string("    ")
      // Control characters never reach the terminal.
      _ if c.to_int() < 0x20 || c.to_int() == 0x7F => buf.write_char('\u{FFFD}')
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Spaces that cover the first `count` code points of `text` (a tab takes 4).
fn padding(text : String, count : Int) -> String {
  let buf = StringBuilder()
  let mut seen = 0
  for c in text {
    if seen >= count {
      break
    }
    buf.write_string(if c == '\t' { "    " } else { " " })
    seen += 1
  }
  buf.to_string()
}

///|
/// The number of code points of `text`.
fn code_points(text : String) -> Int {
  let mut n = 0
  for _ in text {
    n += 1
  }
  n
}

///|
/// The rendered diagnostic of `error` in `source` (named `name` in the
/// location line). Ends with a line break.
pub fn render(
  error : @ast.ParseError,
  source : String,
  name~ : String,
  color? : Bool = false,
) -> String {
  let (message, span, expected, found) = match error {
    Syntax(message~, span~, expected~, found~) =>
      (message, span, expected, found)
    Unsupported(message~, span~) => (message, span, [], "")
  }
  // An error at the end of a source that ends with a line break points at
  // the end of the last line.
  let start = if span.start >= source.length() && source.has_suffix("\r\n") {
    source.length() - 2
  } else if span.start >= source.length() && source.has_suffix("\n") {
    source.length() - 1
  } else {
    span.start
  }
  let at = position(source, start)
  // A moved end-of-input position, or an empty span, marks one character.
  let end_offset = if start != span.start || span.end <= start {
    start
  } else {
    span.end
  }
  let stop = position(source, end_offset)
  let text = line_text(source, at.line)
  let line_length = code_points(text)
  let marks = if stop.line > at.line {
    line_length - (at.column - 1)
  } else {
    stop.column - at.column
  }
  let marks = if marks < 1 { 1 } else { marks }
  let gutter = "\{at.line}".length()
  let pad = " ".repeat(gutter)
  let expected_kind = message.has_prefix("expected")
  let header = if expected_kind && found != "" {
    message + ", found " + found
  } else {
    message
  }
  let buf = StringBuilder()
  buf.write_string(paint("error", red, color))
  buf.write_string(paint(": " + header, bold, color))
  buf.write_string("\n")
  buf.write_string(
    pad + paint("-->", blue, color) + " \{name}:\{at.line}:\{at.column}\n",
  )
  buf.write_string(pad + " " + paint("|", blue, color) + "\n")
  buf.write_string(
    paint("\{at.line}", blue, color) +
    " " +
    paint("|", blue, color) +
    " " +
    expand(text) +
    "\n",
  )
  let label = if expected_kind { " " + message } else { "" }
  buf.write_string(
    pad +
    " " +
    paint("|", blue, color) +
    " " +
    padding(text, at.column - 1) +
    paint("^".repeat(marks) + label, red, color) +
    "\n",
  )
  let notes : Array[String] = []
  if stop.line > at.line {
    notes.push("note: the span ends at line \{stop.line}")
  }
  if expected.length() >= 2 {
    notes.push("expected: " + or_list(expected))
  }
  if !notes.is_empty() {
    buf.write_string(pad + " " + paint("|", blue, color) + "\n")
    for note in notes {
      buf.write_string(pad + " " + paint("=", blue, color) + " " + note + "\n")
    }
  }
  buf.to_string()
}
