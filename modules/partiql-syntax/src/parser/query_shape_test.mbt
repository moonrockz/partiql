// Test support: query shapes.

///|
fn opt_alias(prefix : String, i : @ast.Identifier?) -> String {
  match i {
    Some(x) => " \{prefix} \{ident_shape(x)}"
    None => ""
  }
}

///|
fn from_shape(f : @ast.FromItem) -> String {
  match f {
    Scan(s) =>
      "\{if s.lateral { "lateral " } else { "" }}\{shape(s.expr)}\{opt_alias("as", s.as_)}\{opt_alias("at", s.at)}\{opt_alias("by", s.by)}"
    Unpivot(s) =>
      "(unpivot \{shape(s.expr)}\{opt_alias("as", s.as_)}\{opt_alias("at", s.at)}\{opt_alias("by", s.by)})"
    Join(j) => {
      let kind = match j.kind {
        Inner => "inner"
        Left => "left"
        Right => "right"
        Full => "full"
      }
      match j.form {
        Comma => "(, \{from_shape(j.left)} \{from_shape(j.right)})"
        Cross => "(\{kind}-cross \{from_shape(j.left)} \{from_shape(j.right)})"
        On(c) =>
          "(\{kind} \{from_shape(j.left)} \{from_shape(j.right)} (on \{shape(c)}))"
      }
    }
  }
}

///|
fn select_shape(s : @ast.Select) -> String {
  let parts : Array[String] = []
  let projection = match s.projection {
    Star(_) => "*"
    Value(e) => "(value \{shape(e)})"
    Pivot(value~, key~) => "(pivot \{shape(value)} \{shape(key)})"
    Items(items) =>
      items
      .map(item => {
        match item {
          Expr(e, as_~, ..) => "\{shape(e)}\{opt_alias("as", as_)}"
          AllFields(e, ..) => "\{shape(e)}.*"
        }
      })
      .join(", ")
  }
  parts.push("\{quantifier_prefix(s.quantifier)}\{projection}")
  if s.from is Some(f) {
    parts.push("(from \{from_shape(f)})")
  }
  for l in s.let_ {
    parts.push("(let \{shape(l.expr)} \{ident_shape(l.name)})")
  }
  if s.where_ is Some(w) {
    parts.push("(where \{shape(w)})")
  }
  if s.group_by is Some(g) {
    let keys = match g.keys {
      All => "all"
      By(ks, partial~) => {
        let text = ks
          .map(k => "\{shape(k.expr)}\{opt_alias("as", k.as_)}")
          .join(", ")
        if partial {
          "partial \{text}"
        } else {
          text
        }
      }
    }
    parts.push("(group \{keys}\{opt_alias("group-as", g.group_as)})")
  }
  if s.having is Some(h) {
    parts.push("(having \{shape(h)})")
  }
  "(select \{parts.join(" ")})"
}

///|
fn query_shape(q : @ast.Query) -> String {
  let body = match q.body {
    Select(s) => select_shape(s)
    Expr(e) => shape(e)
    Table(name) => "(table \{name.map(ident_shape).join(".")})"
    SetOp(op) => {
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
        Some(By(names)) => "-corresponding(\{names.map(ident_shape).join(",")})"
        None => ""
      }
      "(\{outer}\{name}\{quantifier}\{corresponding} \{query_shape(op.left)} \{query_shape(op.right)})"
    }
  }
  let parts : Array[String] = []
  for w in q.with_ {
    parts.push("(with \{ident_shape(w.name)} \{query_shape(w.query)})")
  }
  parts.push(body)
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
      "\{shape(s.expr)}\{order}\{nulls}"
    })
    parts.push("(order \{specs.join(", ")})")
  }
  if q.limit is Some(l) {
    parts.push("(limit \{shape(l)})")
  }
  if q.offset is Some(o) {
    parts.push("(offset \{shape(o)})")
  }
  if parts.length() == 1 {
    parts[0]
  } else {
    "(query \{parts.join(" ")})"
  }
}

///|
fn statement_shape(source : String) -> String raise {
  match @parser.parse_statement(source) {
    Query(q) => query_shape(q)
  }
}
