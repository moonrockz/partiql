// Syntax trees as S-expressions: the shape format of the parser tests.

///|
fn ident_text(i : @ast.Identifier) -> String {
  if i.delimited {
    quoted(i.text, '"')
  } else {
    i.text
  }
}

///|
/// `s` with control characters escaped (`\n`, `\t`, `\r`, `\u{..}`).
fn escape_controls(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    match c {
      '\n' => buf.write_string("\\n")
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      _ if c.to_int() < 0x20 || c.to_int() == 0x7F =>
        buf.write_string("\\u{\{c.to_int().to_string(radix=16)}}")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// `s` between `q` quotes, with `q` doubled inside (PartiQL escaping) and
/// control characters escaped, so that every atom reads back unambiguously.
fn quoted(s : String, q : Char) -> String {
  let doubled = StringBuilder()
  for c in s {
    if c == q {
      doubled.write_char(q)
    }
    doubled.write_char(c)
  }
  "\{q}\{escape_controls(doubled.to_string())}\{q}"
}

///|
fn field_text(f : @ast.DatetimeField) -> String {
  match f {
    Year => "year"
    Month => "month"
    Day => "day"
    Hour => "hour"
    Minute => "minute"
    Second => "second"
    TimezoneHour => "timezone_hour"
    TimezoneMinute => "timezone_minute"
  }
}

///|
fn opt_int(n : Int?) -> String {
  match n {
    Some(v) => "(\{v})"
    None => ""
  }
}

///|
fn qualifier_text(q : @ast.IntervalQualifier) -> String {
  let p = match (q.start_precision, q.fractional_precision) {
    (Some(a), Some(b)) => "(\{a},\{b})"
    (Some(a), None) => "(\{a})"
    _ => ""
  }
  match q.end {
    Some(e) => "\{field_text(q.start)}\{p} to \{field_text(e)}"
    None => "\{field_text(q.start)}\{p}"
  }
}

///|
fn type_text(t : @ast.DataType) -> String {
  match t {
    Null => "NULL"
    Missing => "MISSING"
    Bool => "BOOL"
    TinyInt => "TINYINT"
    SmallInt => "SMALLINT"
    Int => "INT"
    BigInt => "BIGINT"
    Decimal(p, s) =>
      match (p, s) {
        (Some(a), Some(b)) => "DECIMAL(\{a},\{b})"
        _ => "DECIMAL\{opt_int(p)}"
      }
    Numeric(p, s) =>
      match (p, s) {
        (Some(a), Some(b)) => "NUMERIC(\{a},\{b})"
        _ => "NUMERIC\{opt_int(p)}"
      }
    Real => "REAL"
    Double(p) => "DOUBLE\{opt_int(p)}"
    Char(n) => "CHAR\{opt_int(n)}"
    Varchar(n) => "VARCHAR\{opt_int(n)}"
    String => "STRING"
    Symbol => "SYMBOL"
    Blob => "BLOB"
    Clob => "CLOB"
    Date => "DATE"
    Time(p, with_tz~) => "TIME\{opt_int(p)}\{if with_tz { " TZ" } else { "" }}"
    Timestamp(p, with_tz~) =>
      "TIMESTAMP\{opt_int(p)}\{if with_tz { " TZ" } else { "" }}"
    Interval(q) => "INTERVAL \{qualifier_text(q)}"
    Struct => "STRUCT"
    Tuple => "TUPLE"
    List => "LIST"
    Bag => "BAG"
    Sexp => "SEXP"
    Any => "ANY"
    Map(k, v) => "MAP<\{type_text(k)},\{type_text(v)}>"
    Array(Some(e)) => "ARRAY<\{type_text(e)}>"
    Array(None) => "ARRAY"
    Custom(i) => ident_text(i)
  }
}

///|
fn literal_sx(l : @ast.Literal) -> Sx {
  match l {
    Null => Atom("null")
    Missing => Atom("missing")
    Bool(b) => Atom("\{b}")
    Int(t) | Decimal(t) | Float(t) => Atom(t)
    String(s) => Atom(quoted(s, '\''))
    Ion(t, _) => Atom("`\{escape_controls(t)}`")
    Date(s) => list("date", [Atom(quoted(s, '\''))])
    Time(s, precision~, with_tz~) =>
      list(
        "time\{opt_int(precision)}",
        (if with_tz { [Atom("tz")] } else { [] }) + [Atom(quoted(s, '\''))],
      )
    Timestamp(s, precision~, with_tz~) =>
      list(
        "timestamp\{opt_int(precision)}",
        (if with_tz { [Atom("tz")] } else { [] }) + [Atom(quoted(s, '\''))],
      )
    Interval(s, negative~, qualifier~) =>
      list("interval", [
        Atom("\{if negative { "-" } else { "" }}\{quoted(s, '\'')}"),
        Atom(qualifier_text(qualifier)),
      ])
  }
}

///|
fn binary_text(op : @ast.BinaryOp) -> String {
  match op {
    Add => "+"
    Sub => "-"
    Mul => "*"
    Div => "/"
    Mod => "%"
    Concat => "||"
    Eq => "="
    Ne => "<>"
    Lt => "<"
    Le => "<="
    Gt => ">"
    Ge => ">="
  }
}

///|
fn not_prefix(negated : Bool, name : String) -> String {
  if negated {
    "not-\{name}"
  } else {
    name
  }
}

///|
/// The left operand of a left-recursive form.
fn left_child(e : @ast.Expr) -> @ast.Expr? {
  match e.kind {
    Binary(_, a, _)
    | And(a, _)
    | Or(a, _)
    | BoolTest(a, _, ..)
    | Like(a, ..)
    | Between(a, ..)
    | In(a, _, ..)
    | IsNull(a, ..)
    | IsMissing(a, ..)
    | IsType(a, _, ..)
    | Overlaps(a, _) => Some(a)
    _ => None
  }
}

///|
/// A left-recursive node with its left operand already converted.
fn wrap(e : @ast.Expr, left : Sx) -> Sx {
  match e.kind {
    Binary(op, _, b) => list(binary_text(op), [left, expr_sx(b)])
    And(_, b) => list("and", [left, expr_sx(b)])
    Or(_, b) => list("or", [left, expr_sx(b)])
    BoolTest(_, value, negated~) => {
      let v = match value {
        Some(true) => "true"
        Some(false) => "false"
        None => "unknown"
      }
      list("\{not_prefix(negated, "is")}-\{v}", [left])
    }
    Like(_, pattern~, escape~, negated~) =>
      list(
        not_prefix(negated, "like"),
        [left, expr_sx(pattern)] +
        (match escape {
          Some(c) => [expr_sx(c)]
          None => []
        }),
      )
    Between(_, low~, high~, negated~) =>
      list(not_prefix(negated, "between"), [left, expr_sx(low), expr_sx(high)])
    In(_, b, negated~) => list(not_prefix(negated, "in"), [left, expr_sx(b)])
    IsNull(_, negated~) => list("\{not_prefix(negated, "is")}-null", [left])
    IsMissing(_, negated~) =>
      list("\{not_prefix(negated, "is")}-missing", [left])
    IsType(_, t, negated~) =>
      list(not_prefix(negated, "is"), [left, Atom(type_text(t))])
    Overlaps(_, b) => list("overlaps", [left, expr_sx(b)])
    _ => left
  }
}

///|
fn expr_sx(e : @ast.Expr) -> Sx {
  if left_child(e) is None {
    return node_sx(e)
  }
  // A chain such as `a AND b AND c`: walk the left spine with a loop.
  let spine = [e]
  let mut cur = e
  while left_child(cur) is Some(a) && left_child(a) is Some(_) {
    spine.push(a)
    cur = a
  }
  guard left_child(cur) is Some(leaf) else { return node_sx(e) }
  let mut acc = node_sx(leaf)
  for i = spine.length() - 1; i >= 0; i = i - 1 {
    acc = wrap(spine[i], acc)
  }
  acc
}

///|
fn exprs(xs : Array[@ast.Expr]) -> Array[Sx] {
  xs.map(expr_sx)
}

///|
fn field_sx(f : (@ast.Expr, @ast.Expr)) -> Sx {
  Cat([expr_sx(f.0), Atom(":"), expr_sx(f.1)])
}

///|
fn node_sx(e : @ast.Expr) -> Sx {
  match e.kind {
    Lit(l) => literal_sx(l)
    VarRef(i, qualified~) =>
      Atom(if qualified { "@\{ident_text(i)}" } else { ident_text(i) })
    Parameter => Atom("?")
    Error => list("error", [])
    Path(root, steps) => {
      let parts = steps.map(step => {
        match step {
          Field(i) => Atom(".\{ident_text(i)}")
          FieldString(s, ..) => Atom("." + quoted(s, '\''))
          Index(x) => Seq("[", [expr_sx(x)], "]")
          AllElements(_) => Atom("[*]")
          AllFields(_) => Atom(".*")
        }
      })
      list("path", [expr_sx(root)] + parts)
    }
    Unary(Pos, x) => list("pos", [expr_sx(x)])
    Unary(Neg, x) => list("neg", [expr_sx(x)])
    Not(a) => list("not", [expr_sx(a)])
    Case(operand~, branches~, default~) => {
      let parts : Array[Sx] = []
      if operand is Some(o) {
        parts.push(expr_sx(o))
      }
      for b in branches {
        parts.push(list("when", [expr_sx(b.0), expr_sx(b.1)]))
      }
      if default is Some(d) {
        parts.push(list("else", [expr_sx(d)]))
      }
      list("case", parts)
    }
    Cast(x, t) => list("cast", [expr_sx(x), Atom(type_text(t))])
    Extract(f, x) => list("extract", [Atom(field_text(f)), expr_sx(x)])
    Trim(spec~, chars~, x) => {
      let parts : Array[Sx] = []
      match spec {
        Some(Both) => parts.push(Atom("both"))
        Some(Leading) => parts.push(Atom("leading"))
        Some(Trailing) => parts.push(Atom("trailing"))
        None => ()
      }
      if chars is Some(c) {
        parts.push(expr_sx(c))
      }
      parts.push(expr_sx(x))
      list("trim", parts)
    }
    Substring(x, start~, length~) =>
      list(
        "substring",
        [expr_sx(x), expr_sx(start)] +
        (match length {
          Some(n) => [expr_sx(n)]
          None => []
        }),
      )
    Position(a, b) => list("position", [expr_sx(a), expr_sx(b)])
    Overlay(x, placing~, from~, for_~) =>
      list(
        "overlay",
        [expr_sx(x), expr_sx(placing), expr_sx(from)] +
        (match for_ {
          Some(n) => [expr_sx(n)]
          None => []
        }),
      )
    Coalesce(xs) => list("coalesce", exprs(xs))
    NullIf(a, b) => list("nullif", [expr_sx(a), expr_sx(b)])
    DateAdd(f, a, b) =>
      list("date_add", [Atom(field_text(f)), expr_sx(a), expr_sx(b)])
    DateDiff(f, a, b) =>
      list("date_diff", [Atom(field_text(f)), expr_sx(a), expr_sx(b)])
    Call(name, args, quantifier~) => {
      let q = match quantifier {
        Some(All) => [Atom("all")]
        Some(Distinct) => [Atom("distinct")]
        None => []
      }
      list("call", [Atom(ident_text(name))] + q + exprs(args))
    }
    CallStar(name) => list("call", [Atom(ident_text(name)), Atom("*")])
    List(xs) => Seq("[", exprs(xs), "]")
    Bag(xs) => Seq("<<", exprs(xs), ">>")
    Sexp(xs) => list("sexp", exprs(xs))
    Struct(fs) => Seq("{", fs.map(field_sx), "}")
    Map(fs) => list("map", fs.map(field_sx))
    Row(xs) => list("row", exprs(xs))
    Values(xs) => list("values", exprs(xs))
    Query(q) => query_sx(q)
    GraphMatch(m) => graph_sx(m)
    // Left-recursive forms go through expr_sx.
    _ => expr_sx(e)
  }
}

///|
/// ` as x`-style suffixes for aliases.
fn alias_atoms(pairs : Array[(String, @ast.Identifier?)]) -> Array[Sx] {
  let out : Array[Sx] = []
  for pair in pairs {
    if pair.1 is Some(i) {
      out.push(Atom(" \{pair.0} \{ident_text(i)}"))
    }
  }
  out
}

///|
fn source_sx(s : @ast.FromSource, unpivot~ : Bool) -> Sx {
  let body = Cat(
    [
      if s.lateral && !unpivot {
        Cat([Atom("lateral "), expr_sx(s.expr)])
      } else {
        expr_sx(s.expr)
      },
    ] +
    alias_atoms([("as", s.as_), ("at", s.at), ("by", s.by)]),
  )
  if unpivot {
    list("unpivot", [body])
  } else {
    body
  }
}

///|
fn join_head(j : @ast.Join) -> String {
  let kind = match j.kind {
    Inner => "inner"
    Left => "left"
    Right => "right"
    Full => "full"
  }
  match j.form {
    Comma => ","
    Cross => "\{kind}-cross"
    On(_) => kind
  }
}

///|
fn from_sx(f : @ast.FromItem) -> Sx {
  match f {
    Scan(s) => source_sx(s, unpivot=false)
    Unpivot(s) => source_sx(s, unpivot=true)
    Join(j) => {
      // A join chain: walk the left spine with a loop.
      let spine = [j]
      let mut cur = j
      while cur.left is Join(inner) {
        spine.push(inner)
        cur = inner
      }
      let mut acc = from_sx(cur.left)
      for i = spine.length() - 1; i >= 0; i = i - 1 {
        let node = spine[i]
        let items = [acc, from_sx(node.right)]
        if node.form is On(c) {
          items.push(list("on", [expr_sx(c)]))
        }
        acc = list(join_head(node), items)
      }
      acc
    }
  }
}

///|
/// Items separated by commas: `a, b as c, d`.
fn comma_items(items : Array[Sx]) -> Array[Sx] {
  let out : Array[Sx] = []
  for i, x in items {
    out.push(if i + 1 < items.length() { Cat([x, Atom(",")]) } else { x })
  }
  out
}

///|
fn select_sx(s : @ast.Select) -> Sx {
  let parts : Array[Sx] = []
  match s.quantifier {
    Some(All) => parts.push(Atom("all"))
    Some(Distinct) => parts.push(Atom("distinct"))
    None => ()
  }
  match s.projection {
    Star(_) => parts.push(Atom("*"))
    Value(e) => parts.push(list("value", [expr_sx(e)]))
    Pivot(value~, key~) =>
      parts.push(list("pivot", [expr_sx(value), expr_sx(key)]))
    Items(items) => {
      let xs = items.map(item => {
        match item {
          Expr(e, as_~, ..) => Cat([expr_sx(e)] + alias_atoms([("as", as_)]))
          AllFields(e, ..) => Cat([expr_sx(e), Atom(".*")])
        }
      })
      parts.append(comma_items(xs))
    }
  }
  if s.from is Some(f) {
    parts.push(list("from", [from_sx(f)]))
  }
  for l in s.let_ {
    parts.push(list("let", [expr_sx(l.expr), Atom(ident_text(l.name))]))
  }
  if s.where_ is Some(w) {
    parts.push(list("where", [expr_sx(w)]))
  }
  if s.group_by is Some(g) {
    let items : Array[Sx] = []
    match g.keys {
      All => items.push(Atom("all"))
      By(ks, partial~) => {
        if partial {
          items.push(Atom("partial"))
        }
        items.append(
          comma_items(
            ks.map(k => Cat([expr_sx(k.expr)] + alias_atoms([("as", k.as_)]))),
          ),
        )
      }
    }
    if g.group_as is Some(a) {
      items.push(Atom("group-as"))
      items.push(Atom(ident_text(a)))
    }
    parts.push(list("group", items))
  }
  if s.having is Some(h) {
    parts.push(list("having", [expr_sx(h)]))
  }
  list("select", parts)
}

///|
fn set_head(op : @ast.SetOp) -> String {
  let name = match op.op {
    Union => "union"
    Intersect => "intersect"
    Except => "except"
  }
  let outer = if op.outer { "outer-" } else { "" }
  let quantifier = match op.quantifier {
    Some(All) => "-all"
    Some(Distinct) => "-distinct"
    None => ""
  }
  let corresponding = match op.corresponding {
    Some(All) => "-corresponding"
    Some(By(names)) => "-corresponding(\{names.map(ident_text).join(",")})"
    None => ""
  }
  "\{outer}\{name}\{quantifier}\{corresponding}"
}

///|
fn plain(q : @ast.Query) -> Bool {
  q.with_.is_empty() &&
  q.order_by.is_empty() &&
  q.limit is None &&
  q.offset is None
}

///|
fn body_sx(b : @ast.QueryBody) -> Sx {
  match b {
    Select(s) => select_sx(s)
    Expr(e) => expr_sx(e)
    Table(name) => list("table", [Atom(name.map(ident_text).join("."))])
    SetOp(op) => {
      // A set-operation chain: walk the left spine with a loop.
      let spine = [op]
      let mut cur = op
      while plain(cur.left) && cur.left.body is SetOp(inner) {
        spine.push(inner)
        cur = inner
      }
      let mut acc = query_sx(cur.left)
      for i = spine.length() - 1; i >= 0; i = i - 1 {
        acc = list(set_head(spine[i]), [acc, query_sx(spine[i].right)])
      }
      acc
    }
  }
}

///|
fn query_sx(q : @ast.Query) -> Sx {
  let parts : Array[Sx] = []
  for w in q.with_ {
    parts.push(list("with", [Atom(ident_text(w.name)), query_sx(w.query)]))
  }
  parts.push(body_sx(q.body))
  if !q.order_by.is_empty() {
    let specs = q.order_by.map(s => {
      let order = match s.order {
        Some(Asc) => " asc"
        Some(Desc) => " desc"
        None => ""
      }
      let nulls = match s.nulls {
        Some(First) => " nulls-first"
        Some(Last) => " nulls-last"
        None => ""
      }
      Cat([expr_sx(s.expr), Atom(order + nulls)])
    })
    parts.push(list("order", comma_items(specs)))
  }
  if q.limit is Some(l) {
    parts.push(list("limit", [expr_sx(l)]))
  }
  if q.offset is Some(o) {
    parts.push(list("offset", [expr_sx(o)]))
  }
  if parts.length() == 1 {
    parts[0]
  } else {
    list("query", parts)
  }
}

///|
fn label_sx(l : @ast.Label) -> Sx {
  match l.kind {
    Name(i) => Atom(ident_text(i))
    Wildcard => Atom("%")
    Not(x) => list("!", [label_sx(x)])
    And(a, b) => list("&", [label_sx(a), label_sx(b)])
    Or(a, b) => list("|", [label_sx(a), label_sx(b)])
  }
}

///|
fn quantifier_sx(q : @ast.Quantifier?) -> Array[Sx] {
  match q {
    None => []
    Some({ kind: Plus, .. }) => [Atom("+")]
    Some({ kind: Star, .. }) => [Atom("*")]
    Some({ kind: Range(lower~, upper=Some(u)), .. }) =>
      [Atom("{\{lower},\{u}}")]
    Some({ kind: Range(lower~, upper=None), .. }) => [Atom("{\{lower},}")]
  }
}

///|
fn element_sx(
  variable : @ast.Identifier?,
  label : @ast.Label?,
  where_ : @ast.Expr?,
) -> Array[Sx] {
  let parts : Array[Sx] = []
  if variable is Some(v) {
    parts.push(Atom(ident_text(v)))
  }
  if label is Some(l) {
    parts.push(Cat([Atom(":"), label_sx(l)]))
  }
  if where_ is Some(w) {
    parts.push(list("where", [expr_sx(w)]))
  }
  parts
}

///|
fn direction_text(d : @ast.EdgeDirection) -> String {
  match d {
    Left => "<-"
    Undirected => "~"
    Right => "->"
    LeftOrUndirected => "<~"
    UndirectedOrRight => "~>"
    LeftOrRight => "<->"
    Any => "-"
  }
}

///|
fn part_sx(p : @ast.PathPart) -> Sx {
  match p {
    Node(n) => list("node", element_sx(n.variable, n.label, n.where_))
    Edge(e) => {
      let filler = match e.filler {
        Some(f) => [Seq("[", element_sx(f.variable, f.label, f.where_), "]")]
        None => []
      }
      list(
        "edge",
        [Atom(direction_text(e.direction))] +
        filler +
        quantifier_sx(e.quantifier),
      )
    }
    Group(g) => {
      let delimiter = match g.delimiter {
        Paren => "paren"
        Bracket => "bracket"
      }
      let where_ = match g.where_ {
        Some(w) => [list("where", [expr_sx(w)])]
        None => []
      }
      list(
        "group",
        [Atom(delimiter), path_sx(g.path)] +
        where_ +
        quantifier_sx(g.quantifier),
      )
    }
  }
}

///|
fn path_sx(p : @ast.PathPattern) -> Sx {
  let parts : Array[Sx] = []
  match p.restrictor {
    Some(Walk) => parts.push(Atom("walk"))
    Some(Trail) => parts.push(Atom("trail"))
    Some(Acyclic) => parts.push(Atom("acyclic"))
    Some(Simple) => parts.push(Atom("simple"))
    None => ()
  }
  if p.variable is Some(v) {
    parts.push(Atom("\{ident_text(v)} ="))
  }
  parts.append(p.parts.map(part_sx))
  list("path", parts)
}

///|
fn selector_sx(s : @ast.Selector) -> Sx {
  match s.kind {
    AnyShortest => Atom("any-shortest")
    AllShortest => Atom("all-shortest")
    Shortest => Atom("shortest")
    Any(k=None) => Atom("any")
    Any(k=Some(k)) => list("any", [Atom("\{k}")])
    ShortestK(k~, group~) =>
      list(
        "shortest",
        [Atom("\{k}")] + (if group { [Atom("group")] } else { [] }),
      )
  }
}

///|
fn graph_sx(m : @ast.GraphMatch) -> Sx {
  let parts = [expr_sx(m.graph)]
  if m.pattern.selector is Some(s) {
    parts.push(selector_sx(s))
  }
  parts.append(m.pattern.paths.map(path_sx))
  if m.pattern.where_ is Some(w) {
    parts.push(list("where", [expr_sx(w)]))
  }
  list("match", parts)
}

///|
/// The S-expression of a statement, laid out to `width` (spec M3c §7).
pub fn to_sexp(statement : @ast.Statement, width? : Int = 80) -> String {
  match statement {
    Query(q) => layout(query_sx(q), width)
    Error(_) => layout(list("error", []), width)
  }
}

///|
/// The S-expression of a query.
pub fn query_to_sexp(query : @ast.Query, width? : Int = 80) -> String {
  layout(query_sx(query), width)
}

///|
/// The S-expression of an expression.
pub fn expr_to_sexp(expr : @ast.Expr, width? : Int = 80) -> String {
  layout(expr_sx(expr), width)
}
