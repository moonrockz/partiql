// Test support: random graph patterns (M2b spec section 10). A GraphSpec
// renders to source text and to the shape that the parser must produce. The
// oracle does not parse patterns; it uses `expr_shape` only for the host
// WHERE expressions, which M2 tests on their own.

///|
/// Identifiers, including the words that the rules of spec 7.4 and 7.5 must
/// not take for selectors or restrictors.
let gen_names : Array[String] = [
  "a", "b", "x1", "City", "any", "walk", "trail", "acyclic", "simple", "Any", "TRAIL",
  "\"q\"", "\"all\"",
]

///|
/// Host WHERE expressions with operators that overlap GPML tokens.
let gen_wheres : Array[String] = [
  "x.a = 1", "x.b != 'z'", "a % 2 = 0", "a || b = 'ab'", "x.n < 3", "x.n - 1 > 0",
  "NOT x.f",
]

///|
let gen_restrictors : Array[String] = ["WALK", "TRAIL", "ACYCLIC", "SIMPLE"]

///|
/// Per direction (in `EdgeDirection` order): the full-form opening, the
/// full-form closing, the abbreviated form, and the shape.
let gen_directions : Array[
  (Array[String], Array[String], Array[String], String),
] = [
  (["<", "-"], ["-"], ["<", "-"], "<-"),
  (["~"], ["~"], ["~"], "~"),
  (["-"], ["-", ">"], ["-", ">"], "->"),
  (["<", "~"], ["~"], ["<", "~"], "<~"),
  (["~"], ["~", ">"], ["~", ">"], "~>"),
  (["<", "-"], ["-", ">"], ["<", "-", ">"], "<->"),
  (["-"], ["-"], ["-"], "-"),
]

///|
enum GLabel {
  LName(String)
  LWild
  LNot(GLabel)
  LAnd(GLabel, GLabel)
  LOr(GLabel, GLabel)
} derive(Debug)

///|
struct GElem {
  name : String?
  label : GLabel?
  where_ : String?
} derive(Debug)

///|
enum GQuant {
  QPlus
  QStar
  QRange(Int, Int?)
} derive(Debug)

///|
enum GPart {
  GNode(GElem)
  /// direction index into `gen_directions`, filler, quantifier
  GEdge(Int, GElem?, GQuant?)
  /// bracket delimiter, path, WHERE, quantifier
  GGroup(Bool, GPath, String?, GQuant?)
} derive(Debug)

///|
struct GPath {
  restrictor : String?
  name : String?
  parts : Array[GPart]
} derive(Debug)

///|
enum GSel {
  SAnyShortest
  SAllShortest
  SShortest
  SAny(Int?)
  SShortestK(Int, Bool)
} derive(Debug)

///|
/// Layout of the rendered text: `spacing` 0 tight, 1 single spaces, 2 random
/// gaps (from `noise`); `case_` 0 upper, 1 lower, 2 capitalized keywords;
/// `full_labels` puts every label in parentheses.
struct Style {
  spacing : Int
  case_ : Int
  full_labels : Bool
  noise : Array[Int]
} derive(Debug)

///|
/// A random parenthesized graph MATCH on the graph `g`.
struct GraphSpec {
  selector : GSel?
  paths : Array[GPath]
  where_ : String?
  style : Style
} derive(Debug)

///|
fn pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
/// True one time in `n`.
fn chance(rs : @splitmix.RandomState, n : Int) -> Bool {
  pick(rs, n) == 0
}

///|
fn gen_name(rs : @splitmix.RandomState) -> String {
  gen_names[pick(rs, gen_names.length())]
}

///|
fn gen_where(rs : @splitmix.RandomState) -> String? {
  if chance(rs, 3) {
    Some(gen_wheres[pick(rs, gen_wheres.length())])
  } else {
    None
  }
}

///|
fn gen_label(rs : @splitmix.RandomState, depth : Int) -> GLabel {
  let k = if depth <= 0 { pick(rs, 2) } else { pick(rs, 5) }
  match k {
    0 => LName(gen_name(rs))
    1 => LWild
    2 => LNot(gen_label(rs, depth - 1))
    3 => LAnd(gen_label(rs, depth - 1), gen_label(rs, depth - 1))
    _ => LOr(gen_label(rs, depth - 1), gen_label(rs, depth - 1))
  }
}

///|
fn gen_elem(rs : @splitmix.RandomState) -> GElem {
  {
    name: if chance(rs, 2) {
      Some(gen_name(rs))
    } else {
      None
    },
    label: if chance(rs, 2) {
      Some(gen_label(rs, 2))
    } else {
      None
    },
    where_: gen_where(rs),
  }
}

///|
fn gen_quant(rs : @splitmix.RandomState) -> GQuant? {
  match pick(rs, 6) {
    0 => Some(QPlus)
    1 => Some(QStar)
    2 => {
      let lower = pick(rs, 4)
      Some(QRange(lower, Some(lower + pick(rs, 3))))
    }
    3 => Some(QRange(pick(rs, 4), None))
    _ => None
  }
}

///|
fn gen_part(rs : @splitmix.RandomState, depth : Int) -> GPart {
  let k = if depth <= 0 { pick(rs, 2) } else { pick(rs, 3) }
  match k {
    0 => GNode(gen_elem(rs))
    1 =>
      GEdge(
        pick(rs, gen_directions.length()),
        if chance(rs, 2) {
          Some(gen_elem(rs))
        } else {
          None
        },
        gen_quant(rs),
      )
    _ =>
      GGroup(
        chance(rs, 2),
        gen_path(rs, depth - 1),
        gen_where(rs),
        gen_quant(rs),
      )
  }
}

///|
fn gen_path(rs : @splitmix.RandomState, depth : Int) -> GPath {
  let parts : Array[GPart] = []
  for _ in 0..<(1 + pick(rs, 4)) {
    let part = gen_part(rs, depth)
    // An abbreviated edge directly before a `[` group reads as a full edge
    // (plan Review Focus 1), so use a `(` group there.
    let part = match (parts.last(), part) {
      (Some(GEdge(_, None, None)), GGroup(true, p, w, q)) =>
        GGroup(false, p, w, q)
      _ => part
    }
    parts.push(part)
  }
  {
    restrictor: if chance(rs, 3) {
      Some(gen_restrictors[pick(rs, gen_restrictors.length())])
    } else {
      None
    },
    name: if chance(rs, 4) {
      Some(gen_name(rs))
    } else {
      None
    },
    parts,
  }
}

///|
impl @quickcheck.Arbitrary for GraphSpec with fn arbitrary(size, rs) {
  let depth = if size < 20 { 1 } else { 2 }
  let selector = match pick(rs, 10) {
    0 => Some(SAnyShortest)
    1 => Some(SAllShortest)
    2 => Some(SShortest)
    3 => Some(SAny(None))
    4 => Some(SAny(Some(pick(rs, 5))))
    5 => Some(SShortestK(pick(rs, 5), chance(rs, 2)))
    _ => None
  }
  let paths = [gen_path(rs, depth)]
  for _ in 0..<(if chance(rs, 3) { 1 + pick(rs, 2) } else { 0 }) {
    paths.push(gen_path(rs, depth))
  }
  let style = {
    spacing: pick(rs, 3),
    case_: pick(rs, 3),
    full_labels: chance(rs, 2),
    noise: Array::makei(16, _ => pick(rs, 5)),
  }
  { selector, paths, where_: gen_where(rs), style, }
}

///|
impl @quickcheck.Shrink for GraphSpec

///|
fn kw(style : Style, word : String) -> String {
  match style.case_ {
    0 => word
    1 => word.to_lower()
    _ =>
      word.view(end_offset=1).to_owned() +
      word.view(start_offset=1).to_owned().to_lower()
  }
}

///|
fn label_prec(l : GLabel) -> Int {
  match l {
    LOr(_, _) => 1
    LAnd(_, _) => 2
    LNot(_) => 3
    _ => 4
  }
}

///|
/// Tokens of `l` with the parentheses that precedence needs (or all of
/// them, for `full`): `|` left associative (1), `&` left associative (2),
/// `!` on a primary (3).
fn label_tokens(
  l : GLabel,
  need : Int,
  full : Bool,
  out : Array[String],
) -> Unit {
  let wrap = full || label_prec(l) < need
  if wrap {
    out.push("(")
  }
  match l {
    LName(n) => out.push(n)
    LWild => out.push("%")
    LNot(x) => {
      out.push("!")
      label_tokens(x, 4, full, out)
    }
    LAnd(a, b) => {
      label_tokens(a, 2, full, out)
      out.push("&")
      label_tokens(b, 3, full, out)
    }
    LOr(a, b) => {
      label_tokens(a, 1, full, out)
      out.push("|")
      label_tokens(b, 2, full, out)
    }
  }
  if wrap {
    out.push(")")
  }
}

///|
fn label_expect(l : GLabel) -> String {
  match l {
    LName(n) => n
    LWild => "%"
    LNot(x) => "(! \{label_expect(x)})"
    LAnd(a, b) => "(& \{label_expect(a)} \{label_expect(b)})"
    LOr(a, b) => "(| \{label_expect(a)} \{label_expect(b)})"
  }
}

///|
fn elem_tokens(e : GElem, style : Style, out : Array[String]) -> Unit {
  if e.name is Some(n) {
    out.push(n)
  }
  if e.label is Some(l) {
    out.push(":")
    label_tokens(l, 1, style.full_labels, out)
  }
  if e.where_ is Some(w) {
    out.push(kw(style, "WHERE"))
    out.push(w)
  }
}

///|
fn elem_expect(e : GElem) -> Array[String] raise {
  let parts : Array[String] = []
  if e.name is Some(n) {
    parts.push(n)
  }
  if e.label is Some(l) {
    parts.push(":\{label_expect(l)}")
  }
  if e.where_ is Some(w) {
    parts.push("(where \{expr_shape(w)})")
  }
  parts
}

///|
fn quant_tokens(q : GQuant?, out : Array[String]) -> Unit {
  match q {
    None => ()
    Some(QPlus) => out.push("+")
    Some(QStar) => out.push("*")
    Some(QRange(lower, upper)) => {
      out.push("{")
      out.push(lower.to_string())
      out.push(",")
      if upper is Some(u) {
        out.push(u.to_string())
      }
      out.push("}")
    }
  }
}

///|
fn quant_expect(q : GQuant?) -> String {
  match q {
    None => ""
    Some(QPlus) => " +"
    Some(QStar) => " *"
    Some(QRange(lower, Some(u))) => " {\{lower},\{u}}"
    Some(QRange(lower, None)) => " {\{lower},}"
  }
}

///|
fn part_tokens(p : GPart, style : Style, out : Array[String]) -> Unit {
  match p {
    GNode(e) => {
      out.push("(")
      elem_tokens(e, style, out)
      out.push(")")
    }
    GEdge(d, filler, q) => {
      let (open, close, abbreviated, _) = gen_directions[d]
      match filler {
        Some(e) => {
          out.append(open)
          out.push("[")
          elem_tokens(e, style, out)
          out.push("]")
          out.append(close)
        }
        None => out.append(abbreviated)
      }
      quant_tokens(q, out)
    }
    GGroup(bracket, path, w, q) => {
      out.push(if bracket { "[" } else { "(" })
      path_tokens(path, style, out)
      if w is Some(x) {
        out.push(kw(style, "WHERE"))
        out.push(x)
      }
      out.push(if bracket { "]" } else { ")" })
      quant_tokens(q, out)
    }
  }
}

///|
fn part_expect(p : GPart) -> String raise {
  match p {
    GNode(e) => {
      let parts = elem_expect(e)
      if parts.is_empty() {
        "(node)"
      } else {
        "(node \{parts.join(" ")})"
      }
    }
    GEdge(d, filler, q) => {
      let filler = match filler {
        Some(e) => " [\{elem_expect(e).join(" ")}]"
        None => ""
      }
      "(edge \{gen_directions[d].3}\{filler}\{quant_expect(q)})"
    }
    GGroup(bracket, path, w, q) => {
      let where_ = match w {
        Some(x) => " (where \{expr_shape(x)})"
        None => ""
      }
      "(group \{if bracket { "bracket" } else { "paren" }} \{path_expect(path)}\{where_}\{quant_expect(q)})"
    }
  }
}

///|
fn path_tokens(p : GPath, style : Style, out : Array[String]) -> Unit {
  if p.restrictor is Some(r) {
    out.push(kw(style, r))
  }
  if p.name is Some(n) {
    out.push(n)
    out.push("=")
  }
  for part in p.parts {
    part_tokens(part, style, out)
  }
}

///|
fn path_expect(p : GPath) -> String raise {
  let parts : Array[String] = []
  if p.restrictor is Some(r) {
    parts.push(r.to_lower())
  }
  if p.name is Some(n) {
    parts.push("\{n} =")
  }
  for part in p.parts {
    parts.push(part_expect(part))
  }
  "(path \{parts.join(" ")})"
}

///|
fn selector_tokens(s : GSel?, style : Style, out : Array[String]) -> Unit {
  match s {
    None => ()
    Some(SAnyShortest) => out.append([kw(style, "ANY"), kw(style, "SHORTEST")])
    Some(SAllShortest) => out.append([kw(style, "ALL"), kw(style, "SHORTEST")])
    Some(SShortest) => out.push(kw(style, "SHORTEST"))
    Some(SAny(None)) => out.push(kw(style, "ANY"))
    Some(SAny(Some(k))) => out.append([kw(style, "ANY"), k.to_string()])
    Some(SShortestK(k, group)) => {
      out.append([kw(style, "SHORTEST"), k.to_string()])
      if group {
        out.push(kw(style, "GROUP"))
      }
    }
  }
}

///|
fn selector_expect(s : GSel) -> String {
  match s {
    SAnyShortest => "any-shortest"
    SAllShortest => "all-shortest"
    SShortest => "shortest"
    SAny(None) => "any"
    SAny(Some(k)) => "(any \{k})"
    SShortestK(k, true) => "(shortest \{k} group)"
    SShortestK(k, false) => "(shortest \{k})"
  }
}

///|
/// The tokens of `g MATCH pattern`; the paths are comma-separated, and the
/// postfilter comes last.
fn match_tokens(spec : GraphSpec, style : Style) -> Array[String] {
  let out = ["g", kw(style, "MATCH")]
  selector_tokens(spec.selector, style, out)
  for i, p in spec.paths {
    if i > 0 {
      out.push(",")
    }
    path_tokens(p, style, out)
  }
  if spec.where_ is Some(w) {
    out.push(kw(style, "WHERE"))
    out.push(w)
  }
  out
}

///|
fn is_word_unit(c : Int) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  c == '_'.to_int() ||
  c == '"'.to_int() ||
  c == '\''.to_int()
}

///|
/// Whether two tokens would lex differently without a space between them:
/// two words, or `-` `-` (a line comment), or `/` `*` and `*` `/`.
fn must_separate(a : String, b : String) -> Bool {
  let last = a.at(a.length() - 1).to_int()
  let first = b.at(0).to_int()
  (is_word_unit(last) && is_word_unit(first)) ||
  (last == '-'.to_int() && first == '-'.to_int()) ||
  (last == '/'.to_int() && first == '*'.to_int()) ||
  (last == '*'.to_int() && first == '/'.to_int())
}

///|
fn layout(tokens : Array[String], style : Style) -> String {
  let buf = StringBuilder()
  for i, t in tokens {
    if i > 0 {
      let gap = match style.spacing {
        0 => ""
        1 => " "
        _ =>
          match style.noise[i % style.noise.length()] {
            0 => ""
            1 => " "
            2 => "\n  "
            3 => " /* c */ "
            _ => " -- c\n"
          }
      }
      let gap = if gap == "" && must_separate(tokens[i - 1], t) {
        " "
      } else {
        gap
      }
      buf.write_string(gap)
    }
    buf.write_string(t)
  }
  buf.to_string()
}

///|
/// `(g MATCH …)`
fn render(spec : GraphSpec) -> String {
  let tokens = ["("]
  tokens.append(match_tokens(spec, spec.style))
  tokens.push(")")
  layout(tokens, spec.style)
}

///|
/// `SELECT * FROM g MATCH …` (the FROM form: first path, no postfilter).
fn render_from(spec : GraphSpec) -> String {
  let single = { ..spec, paths: [spec.paths[0]], where_: None, }
  let tokens = ["SELECT", "*", "FROM"]
  tokens.append(match_tokens(single, spec.style))
  layout(tokens, spec.style)
}

///|
fn expected_shape(spec : GraphSpec) -> String raise {
  let parts = ["g"]
  if spec.selector is Some(s) {
    parts.push(selector_expect(s))
  }
  for p in spec.paths {
    parts.push(path_expect(p))
  }
  if spec.where_ is Some(w) {
    parts.push("(where \{expr_shape(w)})")
  }
  "(match \{parts.join(" ")})"
}
