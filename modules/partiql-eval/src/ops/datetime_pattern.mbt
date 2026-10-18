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
    @value.Value::from_string(format_datetime(xs[0], tokenize(pattern)))
  })
}

///|
/// The rank of a field in the chain year > month > day > hour > minute >
/// second > fraction; `None` for AM/PM, offsets and text.
fn field_order(t : Token) -> Int32? {
  match t {
    Year(_) => Some(0)
    Month(_) => Some(1)
    Day(_) => Some(2)
    Hour24(_) | Hour12(_) => Some(3)
    Minute(_) => Some(4)
    Second(_) => Some(5)
    Fraction(_) | Nano => Some(6)
    _ => None
  }
}

///|
/// Whether a token reads a variable number of digits.
fn variable_width(t : Token) -> Bool {
  match t {
    Year(1)
    | Month(1)
    | Day(1)
    | Hour24(1)
    | Hour12(1)
    | Minute(1)
    | Second(1)
    | Nano => true
    _ => false
  }
}

///|
/// Whether a token reads digits.
fn numeric(t : Token) -> Bool {
  match t {
    Month(3 | 4 | 5) | AmPm | Offset(..) | Literal(_) => false
    _ => true
  }
}

///|
/// The pattern rules of TO_TIMESTAMP (spec M4d3 §4.6, Kotlin v0
/// FormatPattern): no MMMMM, no field twice, a year, an unbroken chain of
/// fields, an offset or AM/PM only with year, month, day and hour, `h` only
/// with `a`, `H` never with `a`, and no variable-width number directly
/// before another number.
fn check_parse_pattern(
  tokens : Array[Token],
  pattern : String,
) -> Unit raise OpFailure {
  let seen = Array::make(7, false)
  let mut am_pm = false
  let mut offset = false
  let mut hour12 = false
  let mut hour24 = false
  for i, t in tokens {
    if t is Month(5) {
      raise bad_pattern(pattern, "MMMMM is not valid for TO_TIMESTAMP")
    }
    match t {
      AmPm => {
        if am_pm {
          raise bad_pattern(pattern, "AM/PM twice")
        }
        am_pm = true
      }
      Offset(..) => {
        if offset {
          raise bad_pattern(pattern, "an offset twice")
        }
        offset = true
      }
      Hour12(_) => hour12 = true
      Hour24(_) => hour24 = true
      _ => ()
    }
    if field_order(t) is Some(r) {
      if seen[r] {
        raise bad_pattern(pattern, "a field twice")
      }
      seen[r] = true
    }
    if variable_width(t) && i + 1 < tokens.length() && numeric(tokens[i + 1]) {
      raise bad_pattern(pattern, "a variable-width number before a number")
    }
  }
  if !seen[0] {
    raise bad_pattern(pattern, "no year")
  }
  let mut last = 0
  for r in 0..<7 {
    if seen[r] {
      last = r
    }
  }
  for r in 0..<last {
    if !seen[r] {
      raise bad_pattern(pattern, "a gap in the fields")
    }
  }
  if (offset || am_pm) && last < 3 {
    raise bad_pattern(pattern, "an offset or AM/PM needs a date and an hour")
  }
  if hour12 && !am_pm {
    raise bad_pattern(pattern, "h needs a")
  }
  if hour24 && am_pm {
    raise bad_pattern(pattern, "H with a")
  }
}

///|
/// A cursor over the text of TO_TIMESTAMP.
priv struct Scan {
  chars : Array[Char]
  mut pos : Int32
}

///|
fn no_match(text : String) -> OpFailure {
  DataFailure("'\{text}' does not match the pattern")
}

///|
/// How many digits a number field reads: one letter reads all the digits
/// that follow; a repeated letter, and `S` x n, read exactly that many.
priv enum Width {
  Variable
  Fixed(Int32)
}

///|
/// The width of a field written with `count` letters.
fn letters_width(count : Int32) -> Width {
  if count == 1 {
    Variable
  } else {
    Fixed(count)
  }
}

///|
/// Digits at the cursor, by `width`. A variable-width number may start with
/// `-`, which the range check then rejects. At most 18 digits, so the value
/// fits Int64; more is out of range.
fn Scan::number(
  self : Scan,
  width : Width,
  text : String,
) -> Int64 raise OpFailure {
  let negative = width is Variable &&
    self.pos < self.chars.length() &&
    self.chars[self.pos] == '-'
  if negative {
    self.pos += 1
  }
  let start = self.pos
  while self.pos < self.chars.length() &&
        self.chars[self.pos] >= '0' &&
        self.chars[self.pos] <= '9' &&
        (match width {
          Variable => true
          Fixed(n) => self.pos - start < n
        }) {
    self.pos += 1
  }
  let count = self.pos - start
  if count == 0 || (width is Fixed(n) && count != n) {
    raise no_match(text)
  }
  if count > 18 {
    raise DataFailure("'\{text}' has a number out of range")
  }
  let mut value = 0L
  for i in start..<self.pos {
    value = value * 10L + (self.chars[i].to_int() - '0'.to_int()).to_int64()
  }
  if negative {
    -value
  } else {
    value
  }
}

///|
/// How text compares: KDOC makes only month names and AM/PM case-insensitive;
/// quoted text, separators and the offset `Z` match exactly.
priv enum Letters {
  Exact
  AnyCase
}

///|
/// Whether the text at the cursor starts with `word`; consumes it when it
/// does.
fn Scan::accept(self : Scan, word : String, letters : Letters) -> Bool {
  let w = word.to_array()
  if self.pos + w.length() > self.chars.length() {
    return false
  }
  for i, c in w {
    let t = self.chars[self.pos + i]
    let same = match letters {
      Exact => t == c
      AnyCase => t == c || t.to_ascii_lowercase() == c.to_ascii_lowercase()
    }
    if !same {
      return false
    }
  }
  self.pos += w.length()
  true
}

///|
fn Scan::next_is_digit(self : Scan) -> Bool {
  self.pos < self.chars.length() &&
  self.chars[self.pos] >= '0' &&
  self.chars[self.pos] <= '9'
}

///|
fn Scan::offset(
  self : Scan,
  zulu : Bool,
  width : Int32,
  text : String,
) -> Int32 raise OpFailure {
  if zulu && self.accept("Z", Exact) {
    return 0
  }
  let sign = if self.accept("+", Exact) {
    1
  } else if self.accept("-", Exact) {
    -1
  } else {
    raise no_match(text)
  }
  let hours = self.number(Fixed(2), text)
  let minutes = match width {
    1 => if self.next_is_digit() { self.number(Fixed(2), text) } else { 0L }
    2 | 4 => self.number(Fixed(2), text)
    _ => {
      if !self.accept(":", Exact) {
        raise no_match(text)
      }
      self.number(Fixed(2), text)
    }
  }
  // XXXX and XXXXX (and x) may carry seconds, which must be 0 (KDOC: an
  // offset must land on a minute boundary).
  let seconds = match width {
    4 if self.next_is_digit() => self.number(Fixed(2), text)
    5 if self.accept(":", Exact) => self.number(Fixed(2), text)
    _ => 0L
  }
  if seconds != 0L {
    raise DataFailure("'\{text}' has an offset that is not whole minutes")
  }
  if hours > 23L || minutes > 59L {
    raise DataFailure("'\{text}' has an offset out of range")
  }
  sign * (hours.to_int() * 60 + minutes.to_int())
}

///|
/// TO_TIMESTAMP with a pattern (spec M4d3 §4.6).
fn parse_with_pattern(
  text : String,
  pattern : String,
) -> @value.Value raise OpFailure {
  let tokens = tokenize(pattern)
  check_parse_pattern(tokens, pattern)
  let scan : Scan = { chars: text.to_array(), pos: 0, }
  let mut year = 0L
  let mut month = 1L
  let mut day = 1L
  let mut hour = 0L
  let mut minute = 0L
  let mut second = 0L
  let mut nanos = 0L
  let mut pm : Bool? = None
  let mut offset = 0
  let mut fraction = false
  for token in tokens {
    match token {
      Year(2) => {
        let v = scan.number(Fixed(2), text)
        year = if v < 70L { 2000L + v } else { 1900L + v }
      }
      Year(w) => year = scan.number(letters_width(w), text)
      Month(3 | 4) => {
        let mut found = false
        for i, name in month_names {
          let short = name.view(end_offset=3).to_owned()
          if (token is Month(4) && scan.accept(name, AnyCase)) ||
            (token is Month(3) && scan.accept(short, AnyCase)) {
            month = (i + 1).to_int64()
            found = true
            break
          }
        }
        if !found {
          raise no_match(text)
        }
      }
      Month(w) => month = scan.number(letters_width(w), text)
      Day(w) => day = scan.number(letters_width(w), text)
      Hour24(w) | Hour12(w) => hour = scan.number(letters_width(w), text)
      AmPm =>
        pm = if scan.accept("AM", AnyCase) {
          Some(false)
        } else if scan.accept("PM", AnyCase) {
          Some(true)
        } else {
          raise no_match(text)
        }
      Minute(w) => minute = scan.number(letters_width(w), text)
      Second(w) => second = scan.number(letters_width(w), text)
      Fraction(k) => {
        let v = scan.number(Fixed(k), text)
        let mut scale = 1L
        for _ in 0..<(9 - k) {
          scale = scale * 10L
        }
        nanos = v * scale
        fraction = true
      }
      Nano => {
        nanos = scan.number(Variable, text)
        fraction = true
      }
      Offset(zulu~, width~) => offset = scan.offset(zulu, width, text)
      Literal(s) => if !scan.accept(s, Exact) { raise no_match(text) }
    }
  }
  if scan.pos != scan.chars.length() {
    raise no_match(text)
  }
  let out_of_range = DataFailure("'\{text}' has a field out of range")
  if year < 1L || year > 9999L || month < 1L || month > 12L {
    raise out_of_range
  }
  if day < 1L || day > month_length(year.to_int(), month.to_int()).to_int64() {
    raise out_of_range
  }
  let hour24 = match pm {
    Some(after_noon) => {
      if hour < 1L || hour > 12L {
        raise out_of_range
      }
      hour % 12L + (if after_noon { 12L } else { 0L })
    }
    None => hour
  }
  if hour24 < 0L ||
    hour24 > 23L ||
    minute < 0L ||
    minute > 59L ||
    second < 0L ||
    second > 59L ||
    nanos < 0L ||
    nanos > 999999999L {
    raise out_of_range
  }
  let precision = if fraction { needed_precision(nanos.to_int()) } else { 0 }
  let date = @value.Date::Date(
    year=year.to_int(),
    month=month.to_int(),
    day=day.to_int(),
  ) catch {
    _ => raise out_of_range
  }
  let time = @value.Time::Time(
    hour=hour24.to_int(),
    minute=minute.to_int(),
    second=second.to_int(),
    nanos=nanos.to_int(),
    precision~,
    offset=Some(offset),
  ) catch {
    _ => raise out_of_range
  }
  @value.Value::from_timestamp(@value.Timestamp(date, time))
}

///|
/// TO_TIMESTAMP of Ion timestamp text (the whole string).
fn ion_timestamp_text(text : String) -> @value.Value raise OpFailure {
  let parsed = @ion_core.Timestamp::parse(text) catch {
    _ => raise DataFailure("'\{text}' is not an Ion timestamp")
  }
  let ts = @value.timestamp_of_ion(parsed)
  ignore(checked_date(ts.date))
  @value.Value::from_timestamp(ts)
}

///|
/// `TO_TIMESTAMP(text [, pattern])`.
pub fn text_to_timestamp(
  args : Array[@value.Value],
) -> @value.Value raise OpFailure {
  if args.length() == 1 {
    apply("TO_TIMESTAMP", [Text], args, xs => {
      guard xs[0] is String(text) else {
        raise TypeFailure("TO_TIMESTAMP needs a string")
      }
      ion_timestamp_text(text)
    })
  } else {
    apply("TO_TIMESTAMP", [Text, Text], args, xs => {
      guard xs[0] is String(text) && xs[1] is String(pattern) else {
        raise TypeFailure("TO_TIMESTAMP needs strings")
      }
      parse_with_pattern(text, pattern)
    })
  }
}
