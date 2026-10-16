// The format patterns of TO_STRING and TO_TIMESTAMP (Kotlin v0
// "TimeFormatPattern"; spec M4d3 §4.6).

///|
/// A token of a format pattern. Widths count the repeated letter.
priv enum Token {
  Year(Int32)
  Month(Int32)
  Day(Int32)
  Hour24(Int32)
  Hour12(Int32)
  AmPm
  Minute(Int32)
  Second(Int32)
  Fraction(Int32)
  Nano
  Offset(zulu~ : Bool, width~ : Int32)
  Literal(String)
}

///|
let month_names : Array[String] = [
  "January", "February", "March", "April", "May", "June", "July", "August", "September",
  "October", "November", "December",
]

///|
fn bad_pattern(pattern : String, why : String) -> OpFailure {
  DataFailure("invalid format pattern '\{pattern}': \{why}")
}

///|
/// The symbol of a run of `count` letters `c`; `None` for a run the pattern
/// language does not have.
fn symbol(c : Char, count : Int32) -> Token? {
  match (c, count) {
    ('y', 1 | 2 | 4) => Some(Year(count))
    ('M', 1..<=5) => Some(Month(count))
    ('d', 1 | 2) => Some(Day(count))
    ('H', 1 | 2) => Some(Hour24(count))
    ('h', 1 | 2) => Some(Hour12(count))
    ('a', 1) => Some(AmPm)
    ('m', 1 | 2) => Some(Minute(count))
    ('s', 1 | 2) => Some(Second(count))
    ('S', 1..<=9) => Some(Fraction(count))
    ('n', 1) => Some(Nano)
    ('X', 1..<=5) => Some(Offset(zulu=true, width=count))
    ('x', 1..<=5) => Some(Offset(zulu=false, width=count))
    _ => None
  }
}

///|
fn is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
/// The tokens of a pattern: runs of one ASCII letter are symbols, `'...'` is
/// quoted text (`''` is one quote), and any other character is itself.
fn tokenize(pattern : String) -> Array[Token] raise OpFailure {
  let chars = pattern.to_array()
  let n = chars.length()
  let out : Array[Token] = []
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '\'' {
      if i + 1 < n && chars[i + 1] == '\'' {
        out.push(Literal("'"))
        i += 2
        continue
      }
      let buf = StringBuilder()
      i += 1
      let mut closed = false
      while i < n {
        if chars[i] == '\'' {
          if i + 1 < n && chars[i + 1] == '\'' {
            buf.write_char('\'')
            i += 2
          } else {
            i += 1
            closed = true
            break
          }
        } else {
          buf.write_char(chars[i])
          i += 1
        }
      }
      if !closed {
        raise bad_pattern(pattern, "a quote that is not closed")
      }
      out.push(Literal(buf.to_string()))
    } else if is_ascii_letter(c) {
      let mut j = i
      while j < n && chars[j] == c {
        j += 1
      }
      match symbol(c, j - i) {
        Some(token) => out.push(token)
        None =>
          raise bad_pattern(
            pattern,
            "'\{String::make(j - i, c)}' is not a pattern symbol",
          )
      }
      i = j
    } else {
      out.push(Literal(c.to_string()))
      i += 1
    }
  }
  out
}

///|
fn number_text(n : Int32, width : Int32) -> String {
  padded(n.to_int64(), width)
}

///|
fn offset_text(minutes : Int32, zulu : Bool, width : Int32) -> String {
  if minutes == 0 && zulu {
    return "Z"
  }
  let sign = if minutes < 0 { "-" } else { "+" }
  let a = minutes.abs()
  let hh = number_text(a / 60, 2)
  let mm = number_text(a % 60, 2)
  match width {
    1 => if a % 60 == 0 { sign + hh } else { sign + hh + mm }
    2 | 4 => sign + hh + mm
    _ => sign + hh + ":" + mm
  }
}

///|
/// A datetime formatted by the tokens. A symbol for a field the value lacks
/// is a data failure.
fn format_datetime(
  x : @value.Value,
  tokens : Array[Token],
) -> String raise OpFailure {
  let (date, time) : (@value.Date?, @value.Time?) = match x {
    Date(d) => (Some(d), None)
    Time(t) => (None, Some(t))
    Timestamp(ts) => (Some(ts.date), Some(ts.time))
    _ => raise TypeFailure("TO_STRING of \{kind_name(x)}")
  }
  let lacks = (what : String) => {
    DataFailure("TO_STRING: a \{kind_name(x)} has no \{what}")
  }
  let buf = StringBuilder()
  for token in tokens {
    match token {
      Literal(text) => buf.write_string(text)
      Year(_) | Month(_) | Day(_) => {
        guard date is Some(d) else { raise lacks("date") }
        let text = match token {
          Year(1) => d.year.to_string()
          Year(2) => number_text(d.year % 100, 2)
          Year(w) => number_text(d.year, w)
          Month(3) => month_names[d.month - 1].view(end_offset=3).to_owned()
          Month(4) => month_names[d.month - 1]
          Month(5) => month_names[d.month - 1].view(end_offset=1).to_owned()
          Month(w) => number_text(d.month, w)
          Day(w) => number_text(d.day, w)
          _ => ""
        }
        buf.write_string(text)
      }
      Offset(zulu~, width~) => {
        guard time is Some(t) && t.offset is Some(o) else {
          raise lacks("time zone offset")
        }
        buf.write_string(offset_text(o, zulu, width))
      }
      _ => {
        guard time is Some(t) else { raise lacks("time of day") }
        let text = match token {
          Hour24(w) => number_text(t.hour, w)
          Hour12(w) => {
            let h = t.hour % 12
            number_text(if h == 0 { 12 } else { h }, w)
          }
          AmPm => if t.hour < 12 { "AM" } else { "PM" }
          Minute(w) => number_text(t.minute, w)
          Second(w) => number_text(t.second, w)
          Fraction(k) => number_text(t.nanos, 9).view(end_offset=k).to_owned()
          Nano => t.nanos.to_string()
          _ => ""
        }
        buf.write_string(text)
      }
    }
  }
  buf.to_string()
}

///|
/// `TO_STRING(x, pattern)`.
pub fn datetime_to_string(
  args : Array[@value.Value],
) -> @value.Value raise OpFailure {
  apply("TO_STRING", [Datetime, Text], args, xs => {
    guard xs[1] is String(pattern) else {
      raise TypeFailure("the pattern of TO_STRING must be a string")
    }
    String(format_datetime(xs[0], tokenize(pattern)))
  })
}
