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
    Some(x) => {
      let n = int_of(x, "\{form}.\{name}")
      if n < 0L {
        raise Malformed("\{form}.\{name} must not be negative")
      }
      n
    }
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
      // Check the exponent before any power of ten: a huge exponent must
      // fail fast, not build a huge number.
      if d.exponent < -9 {
        raise Malformed("\{what} has more than 9 fractional digits")
      }
      let digits = if d.exponent < 0 { -d.exponent } else { 0 }
      if d.coefficient.is_zero() {
        return (0, 0, digits)
      }
      if d.exponent > 1 {
        raise Malformed("\{what} is out of range")
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
            if h < -23 || h > 23 || minutes < 0 || minutes > 59 {
              raise Malformed("$time zone \{h}:\{minutes} is out of range")
            }
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
  let interval = @value.IntervalYM::from_parts(
    negative=sign_of(f, form),
    years=optional_int(f, "years", form),
    months=optional_int(f, "months", form),
  ) catch {
    error => raise Malformed(@debug.to_string(error))
  }
  IntervalYM(interval)
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
  let interval = @value.IntervalDT::from_parts(
    negative=sign_of(f, form),
    days=optional_int(f, "days", form),
    hours=optional_int(f, "hours", form),
    minutes=optional_int(f, "minutes", form),
    seconds=optional_int(f, "seconds", form),
    nanos=optional_int(f, "nanos", form),
  ) catch {
    error => raise Malformed(@debug.to_string(error))
  }
  IntervalDT(interval)
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
/// Decodes a map key or value. In a `date` position, a plain day-precision
/// Ion timestamp (how partiql-tests writes `$map::date::...` keys) is a date.
/// Any other form, including `$timestamp`, decodes as usual, so encoded maps
/// round-trip.
fn decode_typed(
  declared : @value.MapType,
  x : @ion_core.IonValue,
) -> @value.Value raise CodecError {
  match (declared, x.kind()) {
    (Date, Timestamp(ts)) if !x.has_annotations() && ts.precision() == Day =>
      Date(@value.timestamp_of_ion(ts).date)
    _ => from_ion(x)
  }
}

///|
/// `$map::<key type>::<value type>::[[k, v], ...]` (RFC 0104).
fn decode_map(x : @ion_core.IonValue) -> @value.Value raise CodecError {
  let names = x.annotations().map(token => token.text())
  guard names is [_, Some(k), Some(v)] else {
    raise Malformed("$map needs exactly a key type and a value type")
  }
  guard @value.MapType::from_name(k) is Some(key_type) else {
    raise Malformed("$map key type \{k} is unknown")
  }
  guard @value.MapType::from_name(v) is Some(value_type) else {
    raise Malformed("$map value type \{v} is unknown")
  }
  let body = x.with_annotations([])
  if body.is_null() {
    return Null
  }
  guard body.kind() is List(items) else {
    raise Malformed("$map must annotate a list of [key, value] pairs")
  }
  let entries : Array[(@value.Value, @value.Value)] = []
  for item in items {
    guard !item.has_annotations() && item.kind() is List([key, value]) else {
      raise Malformed("$map entry is not an unannotated [key, value] pair")
    }
    entries.push((decode_typed(key_type, key), decode_typed(value_type, value)))
  }
  let map = @value.MapValue::new(key_type~, value_type~, entries) catch {
    error => raise Malformed(@debug.to_string(error))
  }
  Map(map)
}

///|
/// A graph id: a symbol or a string.
fn graph_id(x : @ion_core.IonValue, what : String) -> String raise CodecError {
  match x.kind() {
    Symbol(token) if !x.has_annotations() && token.text() is Some(text) => text
    String(text) if !x.has_annotations() => text
    _ => raise Malformed("\{what} must be a symbol or a string")
  }
}

///|
/// The fields of a node or edge struct; `node::`/`edge::` annotations are
/// optional hints and are ignored.
fn graph_element_fields(
  x : @ion_core.IonValue,
  hint : String,
  allowed : Array[String],
) -> Map[String, @ion_core.IonValue] raise CodecError {
  let names = x.annotations().map(token => token.text())
  if !(names is [] || (names is [Some(h)] && h == hint)) {
    raise Malformed("$graph \{hint} has an unexpected annotation")
  }
  let f = field_map(x.with_annotations([]), "$graph \{hint}")
  check_fields(f, allowed, "$graph \{hint}")
  f
}

///|
fn labels_of(
  f : Map[String, @ion_core.IonValue],
) -> Array[String] raise CodecError {
  match f.get("labels") {
    None => []
    Some(x) => {
      guard !x.has_annotations() && x.kind() is List(items) else {
        raise Malformed("$graph labels must be a list of strings")
      }
      let out : Array[String] = []
      for item in items {
        guard !item.has_annotations() && item.kind() is String(label) else {
          raise Malformed("$graph labels must be a list of strings")
        }
        out.push(label)
      }
      out
    }
  }
}

///|
fn payload_of(
  f : Map[String, @ion_core.IonValue],
) -> @value.Value? raise CodecError {
  match f.get("payload") {
    None => None
    Some(x) =>
      match from_ion(x) {
        Missing => raise Malformed("a $graph payload must not be MISSING")
        v => Some(v)
      }
  }
}

///|
/// `(a -> b)`, `(a -- b)` or `(a <- b)`.
fn ends_of(x : @ion_core.IonValue) -> @value.Ends raise CodecError {
  guard !x.has_annotations() && x.kind() is Sexp([a, op, b]) else {
    raise Malformed("$graph edge ends must be (a -> b), (a -- b) or (a <- b)")
  }
  let from = graph_id(a, "$graph edge end")
  let to = graph_id(b, "$graph edge end")
  match op.kind() {
    Symbol(token) if !op.has_annotations() =>
      match token.text() {
        Some("->") => Directed(from~, to~)
        Some("<-") => Directed(from=to, to=from)
        Some("--") => Undirected(from, to)
        _ => raise Malformed("$graph edge ends need ->, -- or <-")
      }
    _ => raise Malformed("$graph edge ends need ->, -- or <-")
  }
}

///|
fn graph_list(
  f : Map[String, @ion_core.IonValue],
  name : String,
) -> Array[@ion_core.IonValue] raise CodecError {
  match f.get(name) {
    Some(x) if !x.has_annotations() && x.kind() is List(items) => items
    _ => raise Malformed("$graph needs a list of \{name}")
  }
}

///|
/// `$graph::{nodes: [...], edges: [...]}` (the external graph format of
/// RFC 0025).
fn decode_graph(x : @ion_core.IonValue) -> @value.Value raise CodecError {
  if x.annotations().length() != 1 {
    raise Malformed("$graph takes no further annotations")
  }
  let f = field_map(x.with_annotations([]), "$graph")
  check_fields(f, ["nodes", "edges"], "$graph")
  let nodes : Array[@value.GraphNode] = []
  for item in graph_list(f, "nodes") {
    let n = graph_element_fields(item, "node", ["id", "labels", "payload"])
    nodes.push(
      @value.GraphNode::new(
        id=graph_id(required(n, "id", "$graph node"), "$graph node id"),
        labels=labels_of(n),
        payload=payload_of(n),
      ),
    )
  }
  let edges : Array[@value.GraphEdge] = []
  for item in graph_list(f, "edges") {
    let e = graph_element_fields(item, "edge", [
      "id", "labels", "payload", "ends",
    ])
    edges.push(
      @value.GraphEdge::new(
        id=graph_id(required(e, "id", "$graph edge"), "$graph edge id"),
        ends=ends_of(required(e, "ends", "$graph edge")),
        labels=labels_of(e),
        payload=payload_of(e),
      ),
    )
  }
  let graph = @value.GraphValue::new(nodes, edges) catch {
    error => raise Malformed(@debug.to_string(error))
  }
  Graph(graph)
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
  if form == "$map" {
    return decode_map(x)
  }
  if form == "$graph" {
    return decode_graph(x)
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
