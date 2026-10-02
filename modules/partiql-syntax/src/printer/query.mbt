// Queries: SELECT, FROM, joins, clauses, set operations, WITH, TABLE, VALUES.

///|
fn has_clauses(q : @ast.Query) -> Bool {
  !q.with_.is_empty() ||
  !q.order_by.is_empty() ||
  q.limit is Some(_) ||
  q.offset is Some(_)
}

///|
fn Printer::query(self : Printer, q : @ast.Query) -> Doc {
  let lead = self.leading(q.span)
  let words : Array[Doc] = []
  if !q.with_.is_empty() {
    let bindings = q.with_.map(w => {
      cat([
        self.leading(w.span),
        ident_doc(w.name),
        Text(" AS "),
        parens(self.query(w.query)),
      ])
    })
    words.push(cat([Text("WITH "), sep(bindings, ", ")]))
  }
  words.push(self.body(q.body))
  if !q.order_by.is_empty() {
    words.push(
      cat([Text("ORDER BY "), sep(q.order_by.map(s => self.sort_spec(s)), ", ")]),
    )
  }
  if q.limit is Some(l) {
    words.push(cat([Text("LIMIT "), self.full(l)]))
  }
  if q.offset is Some(o) {
    words.push(cat([Text("OFFSET "), self.full(o)]))
  }
  cat([lead, spaced(words)])
}

///|
fn Printer::sort_spec(self : Printer, s : @ast.SortSpec) -> Doc {
  cat([
    self.leading(s.span),
    self.full(s.expr),
    Text(
      match s.order {
        Some(Asc) => " ASC"
        Some(Desc) => " DESC"
        None => ""
      },
    ),
    Text(
      match s.nulls {
        Some(First) => " NULLS FIRST"
        Some(Last) => " NULLS LAST"
        None => ""
      },
    ),
  ])
}

///|
fn Printer::body(self : Printer, b : @ast.QueryBody) -> Doc {
  match b {
    Select(s) => self.select(s)
    SetOp(op) => self.set_op(op)
    Expr(e) => self.expr(e)
    Table(names) => cat([Text("TABLE "), sep(names.map(ident_doc), ".")])
  }
}

///|
/// INTERSECT binds tighter than UNION and EXCEPT.
fn set_level(k : @ast.SetOpKind) -> Int {
  match k {
    Intersect => 2
    Union | Except => 1
  }
}

///|
fn Printer::set_operand(self : Printer, q : @ast.Query, min : Int) -> Doc {
  let needs = has_clauses(q) ||
    (match q.body {
      SetOp(op) => set_level(op.op) < min
      _ => false
    })
  if needs {
    let lead = self.leading(q.span)
    cat([lead, parens(self.query(q))])
  } else {
    self.query(q)
  }
}

///|
fn Printer::set_op(self : Printer, op : @ast.SetOp) -> Doc {
  let l = set_level(op.op)
  let words : Array[Doc] = [self.set_operand(op.left, l)]
  if op.outer {
    words.push(Text("OUTER"))
  }
  words.push(
    Text(
      match op.op {
        Union => "UNION"
        Intersect => "INTERSECT"
        Except => "EXCEPT"
      },
    ),
  )
  match op.quantifier {
    Some(All) => words.push(Text("ALL"))
    Some(Distinct) => words.push(Text("DISTINCT"))
    None => ()
  }
  match op.corresponding {
    Some(All) => words.push(Text("CORRESPONDING"))
    Some(By(names)) =>
      words.push(
        cat([
          Text("CORRESPONDING BY ("),
          sep(names.map(ident_doc), ", "),
          Text(")"),
        ]),
      )
    None => ()
  }
  // Left associative: a right operand at the same level takes parentheses.
  words.push(self.set_operand(op.right, l + 1))
  spaced(words)
}

///|
fn Printer::select(self : Printer, s : @ast.Select) -> Doc {
  let lead = self.leading(s.span)
  let words : Array[Doc] = []
  match s.projection {
    Pivot(value~, key~) => {
      words.push(Text("PIVOT"))
      words.push(self.full(value))
      words.push(Text("AT"))
      words.push(self.full(key))
    }
    projection => {
      words.push(Text("SELECT"))
      match s.quantifier {
        Some(Distinct) => words.push(Text("DISTINCT"))
        Some(All) => words.push(Text("ALL"))
        None => ()
      }
      words.push(self.projection(projection))
    }
  }
  if s.from is Some(f) {
    words.push(Text("FROM"))
    words.push(self.from_item(f))
  }
  if !s.let_.is_empty() {
    let bindings = s.let_.map(l => {
      cat([
        self.leading(l.span),
        self.full(l.expr),
        Text(" AS "),
        ident_doc(l.name),
      ])
    })
    words.push(cat([Text("LET "), sep(bindings, ", ")]))
  }
  if s.where_ is Some(w) {
    words.push(Text("WHERE"))
    words.push(self.full(w))
  }
  if s.group_by is Some(g) {
    words.push(self.group_by(g))
  }
  if s.having is Some(h) {
    words.push(Text("HAVING"))
    words.push(self.full(h))
  }
  cat([lead, spaced(words)])
}

///|
fn Printer::projection(self : Printer, p : @ast.Projection) -> Doc {
  match p {
    Star(_) => Text("*")
    Value(e) => cat([Text("VALUE "), self.full(e)])
    Pivot(..) => Nil
    Items(items) => {
      let docs = items.map(i => {
        match i {
          Expr(e, as_~, span~) => {
            let lead = self.leading(span)
            match as_ {
              Some(a) => cat([lead, self.full(e), Text(" AS "), ident_doc(a)])
              None => cat([lead, self.full(e)])
            }
          }
          AllFields(e, span~) =>
            cat([self.leading(span), self.path_base(e), Text(".*")])
        }
      })
      sep(docs, ", ")
    }
  }
}

///|
fn Printer::group_by(self : Printer, g : @ast.GroupBy) -> Doc {
  let lead = self.leading(g.span)
  let words : Array[Doc] = [Text("GROUP")]
  match g.keys {
    All => {
      words.push(Text("ALL"))
      if g.group_as is Some(a) {
        words.push(Text("AS"))
        words.push(ident_doc(a))
      }
    }
    By(keys, partial~) => {
      if partial {
        words.push(Text("PARTIAL"))
      }
      words.push(Text("BY"))
      let docs = keys.map(k => {
        let d = cat([self.leading(k.span), self.full(k.expr)])
        match k.as_ {
          Some(a) => cat([d, Text(" AS "), ident_doc(a)])
          None => d
        }
      })
      words.push(sep(docs, ", "))
      if g.group_as is Some(a) {
        words.push(Text("GROUP AS"))
        words.push(ident_doc(a))
      }
    }
  }
  cat([lead, spaced(words)])
}

///|
fn Printer::from_item(self : Printer, f : @ast.FromItem) -> Doc {
  match f {
    Scan(s) => self.from_source(s, unpivot=false)
    Unpivot(s) => self.from_source(s, unpivot=true)
    Join(j) => self.join(j)
  }
}

///|
fn Printer::from_source(
  self : Printer,
  s : @ast.FromSource,
  unpivot~ : Bool,
) -> Doc {
  let lead = self.leading(s.span)
  let words : Array[Doc] = []
  if s.lateral {
    words.push(Text("LATERAL"))
  }
  if unpivot {
    words.push(Text("UNPIVOT"))
  }
  words.push(self.full(s.expr))
  for clause in [("AS", s.as_), ("AT", s.at), ("BY", s.by)] {
    if clause.1 is Some(a) {
      words.push(Text(clause.0))
      words.push(ident_doc(a))
    }
  }
  cat([lead, spaced(words)])
}

///|
fn is_comma(f : @ast.FromItem) -> Bool {
  f is Join({ form: Comma, .. })
}

///|
fn Printer::join(self : Printer, j : @ast.Join) -> Doc {
  let lead = self.leading(j.span)
  match j.form {
    Comma => {
      let left = self.from_item(j.left)
      let right = if is_comma(j.right) {
        parens(self.from_item(j.right))
      } else {
        self.from_item(j.right)
      }
      cat([lead, left, Text(", "), right])
    }
    form => {
      let left = if is_comma(j.left) {
        parens(self.from_item(j.left))
      } else {
        self.from_item(j.left)
      }
      let keyword = match (j.kind, form) {
        (Inner, Cross) => "CROSS JOIN"
        (Left, Cross) => "LEFT CROSS JOIN"
        (Right, Cross) => "RIGHT CROSS JOIN"
        (Full, Cross) => "FULL CROSS JOIN"
        (Inner, _) => "JOIN"
        (Left, _) => "LEFT JOIN"
        (Right, _) => "RIGHT JOIN"
        (Full, _) => "FULL JOIN"
      }
      // The right side of a join is one FROM source: a join there takes
      // parentheses.
      let right = if j.right is Join(_) {
        parens(self.from_item(j.right))
      } else {
        self.from_item(j.right)
      }
      let on = match form {
        On(c) => cat([Text(" ON "), self.full(c)])
        _ => Nil
      }
      cat([lead, left, Text(" " + keyword + " "), right, on])
    }
  }
}
