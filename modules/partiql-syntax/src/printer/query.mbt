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
        sub(self.query(w.query)),
      ])
    })
    words.push(list_clause("WITH", bindings))
  }
  words.push(self.body(q.body))
  if !q.order_by.is_empty() {
    words.push(list_clause("ORDER BY", q.order_by.map(s => self.sort_spec(s))))
  }
  if q.limit is Some(l) {
    words.push(cat([Text("LIMIT "), self.full(l)]))
  }
  if q.offset is Some(o) {
    words.push(cat([Text("OFFSET "), self.full(o)]))
  }
  cat([lead, Group(lines(words))])
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
    cat([lead, sub(self.query(q))])
  } else {
    self.query(q)
  }
}

///|
/// The operator words of a set operation, without its operands.
fn set_op_words(op : @ast.SetOp) -> String {
  let words = [
    if op.outer {
      "OUTER "
    } else {
      ""
    },
    match op.op {
      Union => "UNION"
      Intersect => "INTERSECT"
      Except => "EXCEPT"
    },
    match op.quantifier {
      Some(All) => " ALL"
      Some(Distinct) => " DISTINCT"
      None => ""
    },
  ]
  words.join("")
}

///|
/// A chain of set operations, printed with a loop over the left spine (the
/// parser builds these chains without a depth limit).
fn Printer::set_op(self : Printer, op : @ast.SetOp) -> Doc {
  let spine = [op]
  let leads : Array[Doc] = []
  let mut cur = op
  while !has_clauses(cur.left) &&
        cur.left.body is SetOp(inner) &&
        set_level(inner.op) >= set_level(cur.op) {
    leads.push(self.leading(cur.left.span))
    spine.push(inner)
    cur = inner
  }
  let docs = leads
  docs.push(self.set_operand(cur.left, set_level(cur.op)))
  for i = spine.length() - 1; i >= 0; i = i - 1 {
    let o = spine[i]
    docs.push(Line)
    docs.push(Text(set_op_words(o)))
    match o.corresponding {
      Some(All) => docs.push(Text(" CORRESPONDING"))
      Some(By(names)) =>
        docs.push(
          cat([
            Text(" CORRESPONDING BY ("),
            sep(names.map(ident_doc), ", "),
            Text(")"),
          ]),
        )
      None => ()
    }
    docs.push(Line)
    // Left associative: a right operand at the same level takes parentheses.
    docs.push(self.set_operand(o.right, set_level(o.op) + 1))
  }
  Group(cat(docs))
}

///|
/// A SELECT: each clause is one unit, so that the enclosing query's group
/// puts each clause on its own line when it breaks.
fn Printer::select(self : Printer, s : @ast.Select) -> Doc {
  let lead = self.leading(s.span)
  let clauses : Array[Doc] = []
  let head = "SELECT" +
    (match s.quantifier {
      Some(Distinct) => " DISTINCT"
      Some(All) => " ALL"
      None => ""
    })
  match s.projection {
    Pivot(value~, key~) =>
      clauses.push(
        cat([Text("PIVOT "), self.full(value), Text(" AT "), self.full(key)]),
      )
    Star(_) => clauses.push(Text(head + " *"))
    Value(e) => clauses.push(cat([Text(head + " VALUE "), self.full(e)]))
    Items(items) => clauses.push(list_clause(head, self.select_items(items)))
  }
  if s.from is Some(f) {
    clauses.push(cat([Text("FROM "), self.from_item(f)]))
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
    clauses.push(list_clause("LET", bindings))
  }
  if s.where_ is Some(w) {
    clauses.push(cat([Text("WHERE "), self.full(w)]))
  }
  if s.group_by is Some(g) {
    clauses.push(self.group_by(g))
  }
  if s.having is Some(h) {
    clauses.push(cat([Text("HAVING "), self.full(h)]))
  }
  cat([lead, lines(clauses)])
}

///|
fn Printer::select_items(
  self : Printer,
  items : Array[@ast.SelectItem],
) -> Array[Doc] {
  items.map(i => {
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
}

///|
fn Printer::group_by(self : Printer, g : @ast.GroupBy) -> Doc {
  let lead = self.leading(g.span)
  let group_as = match g.group_as {
    Some(a) => Text(" AS " + ident_text(a))
    None => Nil
  }
  match g.keys {
    All => cat([lead, Text("GROUP ALL"), group_as])
    By(keys, partial~) => {
      let docs = keys.map(k => {
        let d = cat([self.leading(k.span), self.full(k.expr)])
        match k.as_ {
          Some(a) => cat([d, Text(" AS "), ident_doc(a)])
          None => d
        }
      })
      let keyword = if partial { "GROUP PARTIAL BY" } else { "GROUP BY" }
      cat([
        lead,
        list_clause(keyword, docs),
        match g.group_as {
          Some(_) => cat([Text(" GROUP"), group_as])
          None => Nil
        },
      ])
    }
  }
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
  let saved = self.row_calls
  self.row_calls = true
  words.push(self.full(s.expr))
  self.row_calls = saved
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
fn join_keyword(kind : @ast.JoinKind, form : @ast.JoinForm) -> String {
  match (kind, form) {
    (_, Comma) => ","
    (Inner, Cross) => "CROSS JOIN"
    (Left, Cross) => "LEFT CROSS JOIN"
    (Right, Cross) => "RIGHT CROSS JOIN"
    (Full, Cross) => "FULL CROSS JOIN"
    (Inner, _) => "JOIN"
    (Left, _) => "LEFT JOIN"
    (Right, _) => "RIGHT JOIN"
    (Full, _) => "FULL JOIN"
  }
}

///|
/// Whether the left side `left` of join `j` prints in parentheses: a comma
/// join under a JOIN.
fn join_left_parens(j : @ast.Join, left : @ast.FromItem) -> Bool {
  !(j.form is Comma) && is_comma(left)
}

///|
/// A chain of joins, printed with a loop over the left spine (FROM lists and
/// join chains have no depth limit).
fn Printer::join(self : Printer, j : @ast.Join) -> Doc {
  let spine = [j]
  let mut cur = j
  while cur.left is Join(inner) && !join_left_parens(cur, cur.left) {
    spine.push(inner)
    cur = inner
  }
  let docs : Array[Doc] = []
  for node in spine {
    docs.push(self.leading(node.span))
  }
  let rest : Array[Doc] = []
  docs.push(
    if join_left_parens(cur, cur.left) {
      parens(self.from_item(cur.left))
    } else {
      self.from_item(cur.left)
    },
  )
  for i = spine.length() - 1; i >= 0; i = i - 1 {
    let node = spine[i]
    // The right side is one FROM item: a join there (for JOIN), or a comma
    // join (for a comma), takes parentheses.
    let right_parens = match node.form {
      Comma => is_comma(node.right)
      _ => node.right is Join(_)
    }
    let right = if right_parens {
      parens(self.from_item(node.right))
    } else {
      self.from_item(node.right)
    }
    let keyword = join_keyword(node.kind, node.form)
    rest.push(
      if keyword == "," {
        cat([Text(","), Line])
      } else {
        cat([Line, Text(keyword + " ")])
      },
    )
    rest.push(right)
    if node.form is On(c) {
      rest.push(Group(Nest(2, cat([Line, Text("ON "), self.full(c)]))))
    }
  }
  docs.push(Nest(2, cat(rest)))
  Group(cat(docs))
}
