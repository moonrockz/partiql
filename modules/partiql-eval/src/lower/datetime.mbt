// Datetime and interval literals (spec M4a section 4).

///|
priv suberror Malformed {
  Reason(String)
}

///|
/// The value of a run of digits.
fn digits_value(digits : String) -> Int64 raise Malformed {
  try @string.parse_int64(digits, base=10) catch {
    _ => raise Reason("not a number")
  } noraise {
    n => n
  }
}

///|
priv struct Cursor {
  chars : Array[Char]
  mut pos : Int
}

///|
fn Cursor::new(text : String) -> Cursor {
  { chars: text.to_array(), pos: 0, }
}

///|
fn Cursor::peek(self : Cursor) -> Char? {
  if self.pos < self.chars.length() {
    Some(self.chars[self.pos])
  } else {
    None
  }
}

///|
fn Cursor::eat(self : Cursor, c : Char) -> Bool {
  if self.peek() == Some(c) {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Cursor::expect(self : Cursor, c : Char) -> Unit raise Malformed {
  if !self.eat(c) {
    raise Reason("expected '\{c}'")
  }
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// The longest run of digits, which may be empty.
fn Cursor::run(self : Cursor) -> String {
  let buf = StringBuilder()
  while self.peek() is Some(c) && is_digit(c) {
    buf.write_char(c)
    self.pos += 1
  }
  buf.to_string()
}

///|
/// A number of at most 9 digits.
fn Cursor::number(self : Cursor) -> (Int, Int) raise Malformed {
  let digits = self.run()
  if digits.length() == 0 || digits.length() > 9 {
    raise Reason("expected a number of 1 to 9 digits")
  }
  (digits_value(digits).to_int(), digits.length())
}

///|
/// Exactly `n` digits.
fn Cursor::fixed(self : Cursor, n : Int) -> Int raise Malformed {
  let (value, length) = self.number()
  if length != n {
    raise Reason("expected \{n} digits")
  }
  value
}

///|
fn Cursor::finish(self : Cursor) -> Unit raise Malformed {
  if self.pos != self.chars.length() {
    raise Reason("unexpected text at the end")
  }
}

///|
/// Wraps a parser: any `Malformed` or constructor error is a `DataError`.
fn literal_error(
  what : String,
  text : String,
  reason : String,
  span : @ast.Span,
) -> @plan.EvalError {
  DataError(message="invalid \{what} literal '\{text}': \{reason}", span~)
}

///|
fn date_part(c : Cursor) -> @value.Date raise Error {
  let negative = c.eat('-')
  let (year, length) = c.number()
  if length < 4 {
    raise Reason("a year needs 4 digits")
  }
  c.expect('-')
  let month = c.fixed(2)
  c.expect('-')
  let day = c.fixed(2)
  @value.Date::new(year=if negative { -year } else { year }, month~, day~)
}

///|
/// `YYYY-MM-DD`.
pub fn date_literal(
  text : String,
  span~ : @ast.Span,
) -> @value.Date raise @plan.EvalError {
  try {
    let c = Cursor::new(text)
    let d = date_part(c)
    c.finish()
    d
  } catch {
    Reason(reason) => raise literal_error("date", text, reason, span)
    e => raise literal_error("date", text, @debug.to_string(e), span)
  }
}

///|
/// `HH:MM:SS[.f*][(+|-)HH:MM]`. Fraction digits beyond 9 are cut off. With an
/// explicit precision the result is cut down to it, with the nanoseconds of
/// one unit in the last place to add when the next digit rounds up (half up,
/// partiql-tests extract.ion, `TIME (2) '01:23:45.678'`).
fn time_part(
  c : Cursor,
  precision : Int?,
  with_tz : Bool,
) -> (@value.Time, Int) raise Error {
  let hour = c.fixed(2)
  c.expect(':')
  let minute = c.fixed(2)
  c.expect(':')
  let second = c.fixed(2)
  let fraction = if c.eat('.') {
    let digits = c.run()
    if digits.length() == 0 {
      raise Reason("a fraction needs digits")
    }
    digits
  } else {
    ""
  }
  let offset : Int? = if c.eat('Z') {
    Some(0)
  } else if c.peek() is Some('+' | '-') {
    let negative = c.eat('-')
    if !negative {
      c.pos += 1
    }
    let hours = c.fixed(2)
    c.expect(':')
    let minutes = c.fixed(2)
    if hours > 23 || minutes > 59 {
      raise Reason("a time zone offset out of range")
    }
    let total = hours * 60 + minutes
    Some(if negative { -total } else { total })
  } else {
    None
  }
  if with_tz && offset is None {
    raise Reason("WITH TIME ZONE needs an offset")
  }
  // A literal without an explicit precision shows at least one fraction digit,
  // as in `second: 45.0` (partiql-tests time.ion, `time no fractional seconds`).
  let digits = precision.unwrap_or(fraction.length().min(9).max(1))
  let shown = fraction.view(end_offset=fraction.length().min(9)).to_owned()
  let all = digits_value(shown + String::make(9 - shown.length(), '0')).to_int()
  let mut unit = 1
  for _ in 0..<(9 - digits.min(9).max(0)) {
    unit = unit * 10
  }
  let nanos = all - all % unit
  let up = if all % unit * 2 >= unit && unit > 1 { unit } else { 0 }
  (
    @value.Time::new(hour~, minute~, second~, nanos~, precision=digits, offset~),
    up,
  )
}

///|
pub fn time_literal(
  text : String,
  precision : Int?,
  with_tz : Bool,
  span~ : @ast.Span,
) -> @value.Time raise @plan.EvalError {
  try {
    let c = Cursor::new(text)
    let (t, up) = time_part(c, precision, with_tz)
    c.finish()
    if up > 0 {
      @ops.shift_time(t, up.to_int64())
    } else {
      t
    }
  } catch {
    Reason(reason) => raise literal_error("time", text, reason, span)
    e => raise literal_error("time", text, @debug.to_string(e), span)
  }
}

///|
/// `YYYY-MM-DD HH:MM:SS[.f*][(+|-)HH:MM]`; `T` may stand for the space.
pub fn timestamp_literal(
  text : String,
  precision : Int?,
  with_tz : Bool,
  span~ : @ast.Span,
) -> @value.Timestamp raise @plan.EvalError {
  try {
    let c = Cursor::new(text)
    let d = date_part(c)
    if !c.eat(' ') {
      c.expect('T')
    }
    let (t, up) = time_part(c, precision, with_tz)
    c.finish()
    let ts = @value.Timestamp::new(d, t)
    if up > 0 {
      @ops.shift_timestamp(ts, up.to_int64())
    } else {
      ts
    }
  } catch {
    Reason(reason) => raise literal_error("timestamp", text, reason, span)
    e => raise literal_error("timestamp", text, @debug.to_string(e), span)
  }
}

///|
fn field_rank(f : @ast.DatetimeField) -> Int raise Malformed {
  match f {
    Year => 0
    Month => 1
    Day => 2
    Hour => 3
    Minute => 4
    Second => 5
    TimezoneHour | TimezoneMinute =>
      raise Reason("a time zone field is not an interval field")
  }
}

///|
fn rank_field(rank : Int) -> @ast.DatetimeField {
  match rank {
    0 => Year
    1 => Month
    2 => Day
    3 => Hour
    4 => Minute
    _ => Second
  }
}

///|
/// The text between a field and the next one.
fn separator(f : @ast.DatetimeField) -> Char {
  match f {
    Year => '-'
    Day => ' '
    _ => ':'
  }
}

///|
/// The fields from the qualifier's first to its last, in order. A
/// year-month field cannot meet a day-time field.
fn interval_fields(
  q : @ast.IntervalQualifier,
) -> Array[@ast.DatetimeField] raise Malformed {
  let first = field_rank(q.start)
  let last = match q.end {
    Some(f) => field_rank(f)
    None => first
  }
  if last < first || (first <= 1) != (last <= 1) {
    raise Reason("an interval qualifier that is not valid")
  }
  let fields = []
  for rank in first..<=last {
    fields.push(rank_field(rank))
  }
  fields
}

///|
/// The largest value of a field that is not the first.
fn field_limit(f : @ast.DatetimeField) -> Int {
  match f {
    Month => 11
    Hour => 23
    _ => 59
  }
}

///|
/// The magnitude of the numbers in an interval text, by field, in the order
/// of the fields, and the nanoseconds.
fn interval_values(
  text : String,
  q : @ast.IntervalQualifier,
  fields : Array[@ast.DatetimeField],
) -> (Bool, Array[Int64], Int64) raise Malformed {
  let c = Cursor::new(text)
  let negative = c.eat('-')
  if !negative {
    ignore(c.eat('+'))
  }
  let leading = q.start_precision.unwrap_or(2)
  let fraction_digits = q.fractional_precision.unwrap_or(6)
  if fraction_digits < 0 || fraction_digits > 9 {
    raise Reason("a fractional precision out of range")
  }
  let values = []
  let mut nanos = 0L
  for i, f in fields {
    if i > 0 {
      c.expect(separator(fields[i - 1]))
    }
    let digits = c.run()
    if digits.length() == 0 || digits.length() > 18 {
      raise Reason("expected a number")
    }
    if i == 0 && digits.length() > leading {
      raise Reason("more than \{leading} digits in the leading field")
    }
    let value = digits_value(digits)
    if i > 0 && value > field_limit(f).to_int64() {
      raise Reason("a field out of range")
    }
    values.push(value)
    if f is Second && i == fields.length() - 1 && c.eat('.') {
      let fraction = c.run()
      if fraction.length() == 0 || fraction.length() > 9 {
        raise Reason("a fraction of 1 to 9 digits")
      }
      let kept = fraction
        .view(end_offset=fraction.length().min(fraction_digits))
        .to_owned()
      let padded = kept + String::make(9 - kept.length(), '0')
      nanos = digits_value(padded)
    }
  }
  c.finish()
  (negative, values, nanos)
}

///|
/// `'3'`, `'1-5'`, `'2 4:5:10.5'`, ... by the qualifier. `negative` is the
/// sign before the text; a sign inside the text turns it again.
pub fn interval_literal(
  text : String,
  negative~ : Bool,
  qualifier~ : @ast.IntervalQualifier,
  span~ : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  try {
    let fields = interval_fields(qualifier)
    let (inner, values, nanos) = interval_values(text, qualifier, fields)
    let negative = negative != inner
    let mut years = 0L
    let mut months = 0L
    let mut days = 0L
    let mut hours = 0L
    let mut minutes = 0L
    let mut seconds = 0L
    for i, f in fields {
      match f {
        Year => years = values[i]
        Month => months = values[i]
        Day => days = values[i]
        Hour => hours = values[i]
        Minute => minutes = values[i]
        Second => seconds = values[i]
        _ => ()
      }
    }
    if fields[0] is (Year | Month) {
      IntervalYM(@value.IntervalYM::from_parts(negative~, years~, months~))
    } else {
      IntervalDT(
        @value.IntervalDT::from_parts(
          negative~,
          days~,
          hours~,
          minutes~,
          seconds~,
          nanos~,
        ),
      )
    }
  } catch {
    Reason(reason) => raise literal_error("interval", text, reason, span)
    e => raise literal_error("interval", text, @debug.to_string(e), span)
  }
}
