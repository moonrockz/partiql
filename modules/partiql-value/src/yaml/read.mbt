///|
/// Source coordinates are relative to the supplied view. Lines, Unicode-scalar
/// columns and document numbers are 1-based; they are not byte offsets.
pub(all) struct Location {
  document : Int32
  line : Int32
  column : Int32
} derive(Debug, Eq)

///|
pub(all) enum ErrorKind {
  Encoding
  Syntax
  Unsupported
  DuplicateKey
  Limit
  Bindings
} derive(Debug, Eq)

///|
pub(all) suberror YamlError {
  YamlError(kind~ : ErrorKind, location~ : Location?, message~ : String)
} derive(Debug)

///|
pub fn YamlError::message(self : YamlError) -> String {
  let YamlError(kind=_, location~, message~) = self
  match location {
    Some(p) =>
      "YAML document \{p.document} at \{p.line}:\{p.column}: \{message}"
    None => "YAML: " + message
  }
}

///|
priv struct Reader {
  parser : @parser.Parser
  mut document : Int32
  mut nodes_left : Int32
  mut payload_left : Int32
  anchors : Map[Int32, Decoded]
  invalid_character : @parser.Marker?
}

///|
fn Reader::error(
  self : Reader,
  kind : ErrorKind,
  mark : @parser.Marker,
  message : String,
) -> YamlError {
  YamlError(
    kind~,
    location=Some({
      document: self.document,
      line: mark.line,
      column: mark.col + 1,
    }),
    message~,
  )
}

///|
fn Reader::next(
  self : Reader,
) -> (@parser.Event, @parser.Marker) raise YamlError {
  let result = self.parser.next_token() catch {
    @parser.YamlError::UnsupportedVersion(mark~) =>
      raise self.error(Unsupported, mark, "only YAML 1.2 is supported")
    @parser.YamlError::ResourceLimit(mark~, info~) =>
      raise self.error(Limit, mark, info)
    @parser.YamlError::YamlError(mark~, info~) =>
      raise self.error(Syntax, mark, info)
  }
  if self.invalid_character is Some(mark) && result.1.index >= mark.index {
    raise self.error(Syntax, mark, "non-printable character in YAML source")
  }
  result
}

///|
fn digits(s : StringView, radix~ : Int32 = 10) -> Bool {
  !s.is_empty() &&
  s
  .iter()
  .all(c => {
    match c {
      '0'..<='7' => true
      '8'..<='9' => radix >= 10
      'a'..<='f' | 'A'..<='F' => radix == 16
      _ => false
    }
  })
}

///|
fn unsigned(s : StringView) -> StringView {
  match s {
    ['+' | '-', .. rest] => rest
    _ => s
  }
}

///|
fn integer_parts(s : StringView) -> (StringView, Int32)? {
  let (body, radix) = match s {
    ['0', 'o', .. rest] => (rest, 8)
    ['0', 'x', .. rest] => (rest, 16)
    _ => (unsigned(s), 10)
  }
  if digits(body, radix~) {
    Some((if radix == 10 { s } else { body }, radix))
  } else {
    None
  }
}

///|
fn integer(s : String) -> @value.Value? {
  match integer_parts(s) {
    Some((body, radix)) =>
      Some(
        @value.Value::from_bigint(
          @bigint.BigInt::from_string(body.to_owned(), radix~),
        ),
      )
    None => None
  }
}

///|
fn float_spelling(s : StringView) -> Bool {
  let s = unsigned(s)
  let mut i = 0
  let mut count = 0
  while i < s.length() && s[i] >= '0' && s[i] <= '9' {
    i += 1
    count += 1
  }
  if i < s.length() && s[i] == '.' {
    i += 1
    while i < s.length() && s[i] >= '0' && s[i] <= '9' {
      i += 1
      count += 1
    }
  }
  if count == 0 {
    return false
  }
  if i < s.length() && (s[i] == 'e' || s[i] == 'E') {
    i += 1
    return digits(unsigned(s[i:]))
  }
  i == s.length()
}

///|
priv enum CoreTag {
  Str
  Null
  Bool
  Int
  Float
  Seq
  Map
}

///|
fn Reader::tag(
  self : Reader,
  tag : @parser.Tag?,
  fallback : CoreTag,
  nonspecific : CoreTag,
  mark : @parser.Marker,
) -> CoreTag raise YamlError {
  match tag {
    None => fallback
    Some({ handle: "", suffix: "!", }) => nonspecific
    Some(t) =>
      match t.handle + t.suffix {
        "tag:yaml.org,2002:str" => Str
        "tag:yaml.org,2002:null" => Null
        "tag:yaml.org,2002:bool" => Bool
        "tag:yaml.org,2002:int" => Int
        "tag:yaml.org,2002:float" => Float
        "tag:yaml.org,2002:seq" => Seq
        "tag:yaml.org,2002:map" => Map
        name =>
          raise self.error(Unsupported, mark, "unsupported YAML tag: " + name)
      }
  }
}

///|
fn scalar_tag(s : String, style : @parser.TScalarStyle) -> CoreTag {
  if !(style is Plain) {
    return Str
  }
  match s {
    "" | "~" | "null" | "Null" | "NULL" => Null
    "true" | "True" | "TRUE" | "false" | "False" | "FALSE" => Bool
    ".inf"
    | ".Inf"
    | ".INF"
    | "+.inf"
    | "+.Inf"
    | "+.INF"
    | "-.inf"
    | "-.Inf"
    | "-.INF"
    | ".nan"
    | ".NaN"
    | ".NAN" => Float
    _ =>
      if integer_parts(s) is Some(_) {
        Int
      } else if float_spelling(s) {
        Float
      } else {
        Str
      }
  }
}

///|
fn Reader::scalar(
  self : Reader,
  s : String,
  style : @parser.TScalarStyle,
  tag : @parser.Tag?,
  mark : @parser.Marker,
) -> @value.Value raise YamlError {
  let kind = self.tag(tag, scalar_tag(s, style), Str, mark)
  let invalid = () => {
    self.error(
      Unsupported,
      mark,
      "scalar does not match declared YAML tag: " + s,
    )
  }
  match kind {
    Str => @value.Value::from_string(s)
    Null =>
      match s {
        "" | "~" | "null" | "Null" | "NULL" => Null
        _ => raise invalid()
      }
    Bool =>
      match s {
        "true" | "True" | "TRUE" => @value.Value::from_bool(true)
        "false" | "False" | "FALSE" => @value.Value::from_bool(false)
        _ => raise invalid()
      }
    Int =>
      match integer(s) {
        Some(v) => v
        None => raise invalid()
      }
    Float =>
      match s {
        ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF" =>
          @value.Value::from_float(@double.infinity)
        "-.inf" | "-.Inf" | "-.INF" =>
          @value.Value::from_float(@double.neg_infinity)
        ".nan" | ".NaN" | ".NAN" =>
          @value.Value::from_float(@double.not_a_number)
        _ => {
          if !float_spelling(s) {
            raise invalid()
          }
          let decimal = @ion_core.Decimal::parse(
            s.replace(old="e", new="d").replace(old="E", new="d"),
          ) catch {
            e => raise self.error(Limit, mark, e.message())
          }
          @value.Value::from_decimal(decimal)
        }
      }
    Seq | Map =>
      raise self.error(Unsupported, mark, "collection tag on a scalar")
  }
}

///|
priv struct Decoded {
  value : @value.Value
  nodes : Int32
  payload : Int32
  height : Int32
}

///|
fn copy_value(value : @value.Value) -> @value.Value {
  match value {
    List(items) => @value.Value::from_list(items.map(copy_value))
    Tuple(t) =>
      @value.Value::from_tuple(
        @value.Tuple(t.fields().map(f => (f.0, copy_value(f.1)))),
      )
    _ => value
  }
}

///|
fn payload_size(s : String) -> Int32 {
  let mut n = 0
  for c in s {
    let code = c.to_int()
    n += if code <= 0x7f {
      1
    } else if code <= 0x7ff {
      2
    } else if code <= 0xffff {
      3
    } else {
      4
    }
  }
  n
}

///|
fn Reader::node(
  self : Reader,
  event : @parser.Event,
  mark : @parser.Marker,
  depth : Int32,
) -> Decoded raise YamlError {
  if event is Alias(id~) {
    guard self.anchors.get(id) is Some(node) else {
      raise self.error(Syntax, mark, "cyclic or undefined YAML alias")
    }
    if node.nodes > self.nodes_left ||
      node.payload > self.payload_left ||
      depth + node.height > 256 {
      raise self.error(
        Limit,
        mark,
        "alias expansion exceeds node, UTF-8 payload or nesting budget",
      )
    }
    self.nodes_left -= node.nodes
    self.payload_left -= node.payload
    self.parser.charge_alias(node.payload, mark) catch {
      @parser.YamlError::ResourceLimit(mark~, info~) =>
        raise self.error(Limit, mark, info)
      _ => raise self.error(Limit, mark, "alias payload budget exceeded")
    }
    return { ..node, value: copy_value(node.value), }
  }
  if self.nodes_left <= 0 {
    raise self.error(Limit, mark, "expanded node budget exceeded")
  }
  self.nodes_left -= 1
  let (id, node) = match event {
    Scalar(value~, style~, tag~, id~) => {
      let payload = payload_size(value)
      if payload > self.payload_left {
        raise self.error(
          Limit,
          mark,
          "scalar payload exceeds the UTF-8 byte budget",
        )
      }
      self.payload_left -= payload
      (
        id,
        Decoded::{
          value: self.scalar(value, style, tag, mark),
          nodes: 1,
          payload,
          height: 0,
        },
      )
    }
    SequenceStart(tag~, id~) => {
      if !(self.tag(tag, Seq, Seq, mark) is Seq) {
        raise self.error(Unsupported, mark, "tag does not match sequence node")
      }
      if depth >= 256 {
        raise self.error(Limit, mark, "nesting exceeds 256 containers")
      }
      let items = []
      let mut nodes = 1
      let mut payload = 0
      let mut height = 1
      while true {
        let (event, mark) = self.next()
        if event is SequenceEnd {
          break
        }
        let node = self.node(event, mark, depth + 1)
        items.push(node.value)
        nodes += node.nodes
        payload += node.payload
        height = height.max(node.height + 1)
      }
      (
        id,
        Decoded::{
          value: @value.Value::from_list(items),
          nodes,
          payload,
          height,
        },
      )
    }
    MappingStart(tag~, id~) => {
      if !(self.tag(tag, Map, Map, mark) is Map) {
        raise self.error(Unsupported, mark, "tag does not match mapping node")
      }
      if depth >= 256 {
        raise self.error(Limit, mark, "nesting exceeds 256 containers")
      }
      let fields = []
      let names : Map[String, Unit] = Map([])
      let mut nodes = 1
      let mut payload = 0
      let mut height = 1
      while true {
        let (event, mark) = self.next()
        if event is MappingEnd {
          break
        }
        let key = self.node(event, mark, depth + 1)
        guard key.value is String(name) else {
          raise self.error(
            Unsupported,
            mark,
            "mapping keys must be strings; quote the key or use !!str",
          )
        }
        if names.contains(name) {
          raise self.error(DuplicateKey, mark, "duplicate mapping key: " + name)
        }
        names[name] = ()
        let (event, mark) = self.next()
        let node = self.node(event, mark, depth + 1)
        fields.push((name, node.value))
        nodes += key.nodes + node.nodes
        payload += key.payload + node.payload
        height = height.max(node.height + 1)
      }
      (
        id,
        Decoded::{
          value: @value.Value::from_tuple(@value.Tuple(fields)),
          nodes,
          payload,
          height,
        },
      )
    }
    _ => raise self.error(Syntax, mark, "expected a YAML value")
  }
  if id != 0 {
    self.anchors[id] = node
  }
  node
}

///|
/// Decode YAML input without rounding finite numbers through binary64.
pub fn read_text(source : StringView) -> Array[@value.Value] raise YamlError {
  read_limited(source, max_nodes=1000000, max_payload=67108864)
}

///|
fn read_limited(
  source : StringView,
  max_nodes~ : Int32,
  max_payload~ : Int32,
) -> Array[@value.Value] raise YamlError {
  let reader = Reader::{
    parser: @parser.Parser(source, max_nodes~, max_payload~),
    document: 1,
    nodes_left: max_nodes,
    payload_left: max_payload,
    anchors: Map([]),
    invalid_character: invalid_character(source),
  }
  let result = []
  while true {
    let (event, mark) = reader.next()
    match event {
      StreamStart => ()
      StreamEnd => break
      DocumentStart => {
        reader.anchors.clear()
        let (event, mark) = reader.next()
        result.push(reader.node(event, mark, 0).value)
      }
      DocumentEnd => reader.document += 1
      _ => raise reader.error(Syntax, mark, "expected a document")
    }
  }
  result
}

///|
pub fn read_bytes(source : BytesView) -> Array[@value.Value] raise YamlError {
  if source[:source.length().min(4)].iter().any(b => b == 0) {
    raise YamlError(
      kind=Encoding,
      location=None,
      message="expected UTF-8 YAML; UTF-16 and UTF-32 are not supported",
    )
  }
  let text = @utf8.decode(source) catch {
    _ =>
      raise YamlError(
        kind=Encoding,
        location=None,
        message="expected UTF-8 YAML; UTF-16 and UTF-32 are not supported",
      )
  }
  read_text(text)
}

///|
fn invalid_character(source : StringView) -> @parser.Marker? {
  let mut line = 1
  let mut column = 0
  let mut index = 0
  let mut previous_cr = false
  for c in source {
    let n = c.to_int()
    if (n < 32 && c != '\t' && c != '\n' && c != '\r') ||
      (n >= 127 && n <= 159 && n != 133) ||
      (n >= 0xd800 && n <= 0xdfff) ||
      n == 0xfffe ||
      n == 0xffff {
      return Some(@parser.Marker::{ index, line, col: column, })
    }
    if c == '\r' {
      line += 1
      column = 0
    } else if c == '\n' {
      if !previous_cr {
        line += 1
      }
      column = 0
    } else {
      column += 1
    }
    previous_cr = c == '\r'
    index += 1
  }
  None
}
