///|
fn describe(x : @ion_core.IonValue) -> String {
  @debug.to_string(x.ion_type())
}

///|
fn field_map(
  x : @ion_core.IonValue,
  form : String,
) -> Map[String, @ion_core.IonValue] raise CodecError {
  guard x.kind() is Struct(fields) else {
    raise Malformed("\{form} must be a struct, not \{describe(x)}")
  }
  let out : Map[String, @ion_core.IonValue] = Map([])
  for field in fields {
    guard field.name().text() is Some(name) else {
      raise Malformed("\{form} has a field without a name")
    }
    if out.contains(name) {
      raise Malformed("\{form} has the field \{name} twice")
    }
    out[name] = field.value()
  }
  out
}

///|
fn check_fields(
  fields : Map[String, @ion_core.IonValue],
  allowed : Array[String],
  form : String,
) -> Unit raise CodecError {
  for name, _ in fields {
    if !allowed.contains(name) {
      raise Malformed("\{form} has an unknown field \{name}")
    }
  }
}

///|
fn int_of(x : @ion_core.IonValue, what : String) -> Int64 raise CodecError {
  guard x.kind() is Int(n) else {
    raise Malformed("\{what} must be an int, not \{describe(x)}")
  }
  guard @value.Value::integer(n) is Int(small) else {
    raise Malformed("\{what} is out of range")
  }
  small
}

///|
fn small_int(x : @ion_core.IonValue, what : String) -> Int raise CodecError {
  let n = int_of(x, what)
  if n < -2147483648L || n > 2147483647L {
    raise Malformed("\{what} is out of range")
  }
  n.to_int()
}

///|
fn required(
  fields : Map[String, @ion_core.IonValue],
  name : String,
  form : String,
) -> @ion_core.IonValue raise CodecError {
  match fields.get(name) {
    Some(x) => x
    None => raise Malformed("\{form} needs the field \{name}")
  }
}

///|
fn optional_int(
  fields : Map[String, @ion_core.IonValue],
  name : String,
  form : String,
) -> Int64 raise CodecError {
  match fields.get(name) {
    Some(x) => int_of(x, "\{form}.\{name}")
    None => 0L
  }
}

///|
/// An offset field: an int (minutes) or a null (no time zone).
fn offset_of(x : @ion_core.IonValue?, what : String) -> Int? raise CodecError {
  match x {
    None => None
    Some(v) if v.is_null() => None
    Some(v) => Some(small_int(v, what))
  }
}

///|
/// A seconds field: an int or a decimal with at most 9 fractional digits.
/// Returns (second, nanos, precision).
fn seconds_of(
  x : @ion_core.IonValue,
  what : String,
) -> (Int, Int, Int) raise CodecError {
  match x.kind() {
    Int(_) => (small_int(x, what), 0, 0)
    Decimal(d) => {
      let digits = if d.exponent < 0 { -d.exponent } else { 0 }
      if digits > 9 {
        raise Malformed("\{what} has more than 9 fractional digits")
      }
      let scaled = if d.exponent > 0 {
        d.coefficient * 10N.pow(@bigint.BigInt::from_int(d.exponent))
      } else {
        d.coefficient
      }
      let unit = 10N.pow(@bigint.BigInt::from_int(digits))
      let whole = scaled / unit
      let fraction = scaled % unit
      if fraction.compare(0N) < 0 {
        raise Malformed("\{what} is negative")
      }
      let nanos = fraction * 10N.pow(@bigint.BigInt::from_int(9 - digits))
      (
        small_int(@ion_core.IonValue::big_int(whole), what),
        nanos.to_int(),
        digits,
      )
    }
    _ =>
      raise Malformed("\{what} must be an int or a decimal, not \{describe(x)}")
  }
}

///|
fn make_time(
  hour : Int,
  minute : Int,
  sec : (Int, Int, Int),
  offset : Int?,
) -> @value.Time raise CodecError {
  @value.Time::new(
    hour~,
    minute~,
    second=sec.0,
    nanos=sec.1,
    precision=sec.2,
    offset~,
  ) catch {
    error => raise Malformed(@debug.to_string(error))
  }
}

///|
fn make_date(
  year : Int,
  month : Int,
  day : Int,
) -> @value.Date raise CodecError {
  @value.Date::new(year~, month~, day~) catch {
    error => raise Malformed(@debug.to_string(error))
  }
}

///|
fn decode_date(x : @ion_core.IonValue) -> @value.Value raise CodecError {
  match x.kind() {
    Timestamp(ts) => {
      let t = @value.timestamp_of_ion(ts)
      Date(t.date)
    }
    _ => {
      let f = field_map(x, "$date")
      check_fields(f, ["year", "month", "day"], "$date")
      Date(
        make_date(
          small_int(required(f, "year", "$date"), "$date.year"),
          small_int(required(f, "month", "$date"), "$date.month"),
          small_int(required(f, "day", "$date"), "$date.day"),
        ),
      )
    }
  }
}

///|
/// Parses `HH:MM:SS[.fffffffff][(+|-)HH:MM]`.
fn parse_time_text(text : String) -> @value.Time raise CodecError {
  let chars : Array[Char] = text.iter().collect()
  let mut pos = 0
  fn digits(count : Int) -> Int raise CodecError {
    let mut n = 0
    for _ in 0..<count {
      if pos >= chars.length() || chars[pos] < '0' || chars[pos] > '9' {
        raise Malformed("$time text \{text} is not HH:MM:SS")
      }
      n = n * 10 + (chars[pos].to_int() - '0'.to_int())
      pos += 1
    }
    n
  }
  fn expect_char(c : Char) -> Unit raise CodecError {
    if pos >= chars.length() || chars[pos] != c {
      raise Malformed("$time text \{text} is not HH:MM:SS")
    }
    pos += 1
  }
  let hour = digits(2)
  expect_char(':')
  let minute = digits(2)
  expect_char(':')
  let second = digits(2)
  let mut nanos = 0
  let mut precision = 0
  if pos < chars.length() && chars[pos] == '.' {
    pos += 1
    while pos < chars.length() && chars[pos] >= '0' && chars[pos] <= '9' {
      if precision == 9 {
        raise Malformed("$time text \{text} has more than 9 fractional digits")
      }
      nanos = nanos * 10 + (chars[pos].to_int() - '0'.to_int())
      precision += 1
      pos += 1
    }
    for _ in precision..<9 {
      nanos *= 10
    }
  }
  let offset = if pos < chars.length() &&
    (chars[pos] == '+' || chars[pos] == '-') {
    let negative = chars[pos] == '-'
    pos += 1
    let h = digits(2)
    expect_char(':')
    let m = digits(2)
    Some(if negative { -(h * 60 + m) } else { h * 60 + m })
  } else {
    None
  }
  if pos != chars.length() {
    raise Malformed("$time text \{text} has trailing characters")
  }
  make_time(hour, minute, (second, nanos, precision), offset)
}

///|
fn decode_time(x : @ion_core.IonValue) -> @value.Value raise CodecError {
  match x.kind() {
    String(text) => Time(parse_time_text(text))
    _ => {
      let f = field_map(x, "$time")
      let hour = small_int(required(f, "hour", "$time"), "$time.hour")
      let minute = small_int(required(f, "minute", "$time"), "$time.minute")
      let sec = seconds_of(required(f, "second", "$time"), "$time.second")
      let offset = if f.contains("timezone_hour") ||
        f.contains("timezone_minute") {
        check_fields(
          f,
          ["hour", "minute", "second", "timezone_hour", "timezone_minute"],
          "$time",
        )
        match
          (
            offset_of(f.get("timezone_hour"), "$time.timezone_hour"),
            offset_of(f.get("timezone_minute"), "$time.timezone_minute"),
          ) {
          (None, None) => None
          (Some(h), m) => {
            let minutes = m.unwrap_or(0)
            Some(if h < 0 { h * 60 - minutes } else { h * 60 + minutes })
          }
          (None, Some(m)) => Some(m)
        }
      } else {
        check_fields(f, ["hour", "minute", "second", "offset"], "$time")
        offset_of(f.get("offset"), "$time.offset")
      }
      Time(make_time(hour, minute, sec, offset))
    }
  }
}

///|
fn decode_timestamp(x : @ion_core.IonValue) -> @value.Value raise CodecError {
  let form = "$timestamp"
  let f = field_map(x, form)
  check_fields(
    f,
    ["year", "month", "day", "hour", "minute", "second", "offset"],
    form,
  )
  let date = make_date(
    small_int(required(f, "year", form), "\{form}.year"),
    small_int(required(f, "month", form), "\{form}.month"),
    small_int(required(f, "day", form), "\{form}.day"),
  )
  let time = make_time(
    small_int(required(f, "hour", form), "\{form}.hour"),
    small_int(required(f, "minute", form), "\{form}.minute"),
    seconds_of(required(f, "second", form), "\{form}.second"),
    offset_of(f.get("offset"), "\{form}.offset"),
  )
  Timestamp(@value.Timestamp::new(date, time))
}

///|
fn sign_of(
  f : Map[String, @ion_core.IonValue],
  form : String,
) -> Bool raise CodecError {
  match f.get("sign") {
    None => false
    Some(x) =>
      match x.kind() {
        String("+") => false
        String("-") => true
        Symbol(token) if token.text() == Some("+") => false
        Symbol(token) if token.text() == Some("-") => true
        _ => raise Malformed("\{form}.sign must be \"+\" or \"-\"")
      }
  }
}

///|
fn decode_interval_ym(x : @ion_core.IonValue) -> @value.Value raise CodecError {
  let form = "$interval_ym"
  let f = field_map(x, form)
  check_fields(f, ["sign", "years", "months"], form)
  IntervalYM(
    @value.IntervalYM::from_parts(
      negative=sign_of(f, form),
      years=optional_int(f, "years", form),
      months=optional_int(f, "months", form),
    ),
  )
}

///|
fn decode_interval_dt(x : @ion_core.IonValue) -> @value.Value raise CodecError {
  let form = "$interval_dt"
  let f = field_map(x, form)
  check_fields(
    f,
    ["sign", "days", "hours", "minutes", "seconds", "nanos"],
    form,
  )
  IntervalDT(
    @value.IntervalDT::from_parts(
      negative=sign_of(f, form),
      days=optional_int(f, "days", form),
      hours=optional_int(f, "hours", form),
      minutes=optional_int(f, "minutes", form),
      seconds=optional_int(f, "seconds", form),
      nanos=optional_int(f, "nanos", form),
    ),
  )
}

///|
fn decode_plain(x : @ion_core.IonValue) -> @value.Value raise CodecError {
  match x.kind() {
    Null(_) => Null
    Bool(b) => Bool(b)
    Int(n) => @value.Value::integer(n)
    Float(d) => Float(d)
    Decimal(d) => Decimal(d)
    Timestamp(ts) => Timestamp(@value.timestamp_of_ion(ts))
    Symbol(token) =>
      match token.text() {
        Some(text) => String(text)
        None => raise Malformed("symbol without text")
      }
    String(s) => String(s)
    Clob(bytes) => Clob(bytes)
    Blob(bytes) => Blob(bytes)
    List(items) => {
      let out : Array[@value.Value] = []
      for item in items {
        out.push(from_ion(item))
      }
      List(out)
    }
    Sexp(_) => raise Malformed("an s-expression is only valid inside $ion")
    Struct(fields) => {
      let out : Array[(String, @value.Value)] = []
      for field in fields {
        guard field.name().text() is Some(name) else {
          raise Malformed("struct field without a name")
        }
        out.push((name, from_ion(field.value())))
      }
      Tuple(@value.Tuple::new(out))
    }
  }
}

///|
fn without_first_annotation(x : @ion_core.IonValue) -> @ion_core.IonValue {
  let annotations = x.annotations()
  x.with_annotations(annotations[1:].to_owned())
}

///|
/// Decodes a PartiQL-encoded Ion value.
pub fn from_ion(x : @ion_core.IonValue) -> @value.Value raise CodecError {
  let annotations = x.annotations()
  if annotations.is_empty() {
    return decode_plain(x)
  }
  guard annotations[0].text() is Some(form) else {
    raise Malformed("annotation without text")
  }
  if form == "$ion" {
    return Ion(without_first_annotation(x))
  }
  if form == "$map" || form == "$graph" {
    raise Unsupported("\{form} values")
  }
  if annotations.length() != 1 {
    raise Malformed("\{form} takes no further annotations")
  }
  let body = x.with_annotations([])
  match form {
    "$missing" =>
      if body.is_untyped_null() {
        Missing
      } else {
        raise Malformed("$missing must annotate null")
      }
    "$bag" =>
      match body.kind() {
        List(items) => {
          let out : Array[@value.Value] = []
          for item in items {
            out.push(from_ion(item))
          }
          Bag(@value.Bag::new(out))
        }
        _ => raise Malformed("$bag must annotate a list")
      }
    "$date" => decode_date(body)
    "$time" => decode_time(body)
    "$timestamp" => decode_timestamp(body)
    "$interval_ym" => decode_interval_ym(body)
    "$interval_dt" => decode_interval_dt(body)
    _ => raise Malformed("unknown annotation \{form}")
  }
}
