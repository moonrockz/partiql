// Expressions: precedence levels follow the parser's ladder (spec M3a
// section 6, "Parentheses").

///|
/// 1 OR, 2 AND, 3 NOT, 4 IS TRUE/FALSE/UNKNOWN, 5 predicates, 6 ||, 7 + -,
/// 8 * / %, 9 unary signs, 10 primaries. VALUES is 0: it always takes
/// parentheses as an operand.
fn level(e : @ast.Expr) -> Int {
  match e.kind {
    Values(_) => 0
    Or(_, _) => 1
    And(_, _) => 2
    Not(_) => 3
    BoolTest(_, _, ..) => 4
    Binary(Eq | Ne | Lt | Le | Gt | Ge, _, _)
    | Like(_, ..)
    | Between(_, ..)
    | In(_, _, ..)
    | IsNull(_, ..)
    | IsMissing(_, ..)
    | IsType(_, _, ..)
    | Overlaps(_, _) => 5
    Binary(Concat, _, _) => 6
    Binary(Add | Sub, _, _) => 7
    Binary(Mul | Div | Mod, _, _) => 8
    Unary(_, _) => 9
    _ => 10
  }
}

///|
fn binary_info(op : @ast.BinaryOp) -> (Int, String) {
  match op {
    Eq => (5, "=")
    Ne => (5, "<>")
    Lt => (5, "<")
    Le => (5, "<=")
    Gt => (5, ">")
    Ge => (5, ">=")
    Concat => (6, "||")
    Add => (7, "+")
    Sub => (7, "-")
    Mul => (8, "*")
    Div => (8, "/")
    Mod => (8, "%")
  }
}

///|
fn is_number(e : @ast.Expr) -> Bool {
  e.kind is Lit(Int(_) | Decimal(_) | Float(_))
}

///|
fn Printer::expr(self : Printer, e : @ast.Expr) -> Doc {
  let lead = self.leading(e.span)
  cat([lead, self.expr_body(e)])
}

///|
/// `e` in a position that needs at least `min`; in parentheses below it.
fn Printer::operand(self : Printer, e : @ast.Expr, min : Int) -> Doc {
  if level(e) < min {
    let lead = self.leading(e.span)
    cat([lead, parens(self.expr_body(e))])
  } else {
    self.expr(e)
  }
}

///|
/// A position where the parser reads a whole expression.
fn Printer::full(self : Printer, e : @ast.Expr) -> Doc {
  self.operand(e, 1)
}

///|
/// The base of a path step: a primary, and never a bare number (`1.a` would
/// lex as a decimal).
fn Printer::path_base(self : Printer, e : @ast.Expr) -> Doc {
  if level(e) < 10 || is_number(e) {
    let lead = self.leading(e.span)
    cat([lead, parens(self.expr_body(e))])
  } else {
    self.expr(e)
  }
}

///|
fn Printer::items(self : Printer, xs : Array[@ast.Expr]) -> Array[Doc] {
  xs.map(x => self.full(x))
}

///|
fn Printer::fields(
  self : Printer,
  fs : Array[(@ast.Expr, @ast.Expr)],
) -> Array[Doc] {
  fs.map(f => cat([self.full(f.0), Text(": "), self.full(f.1)]))
}

///|
fn Printer::step(self : Printer, s : @ast.PathStep) -> Doc {
  match s {
    Field(i) => cat([Text("."), ident_doc(i)])
    FieldString(t, ..) => Text("." + quote(t, '\''))
    Index(x) => cat([Text("["), self.full(x), Text("]")])
    AllElements(_) => Text("[*]")
    AllFields(_) => Text(".*")
  }
}

///|
fn Printer::expr_body(self : Printer, e : @ast.Expr) -> Doc {
  match e.kind {
    Lit(l) => literal_doc(l)
    VarRef(i, qualified~) =>
      cat([if qualified { Text("@") } else { Nil }, ident_doc(i)])
    Parameter => Text("?")
    Error => Text("/* error */")
    Path(base, steps) => {
      let docs = [self.path_base(base)]
      for s in steps {
        docs.push(self.step(s))
      }
      cat(docs)
    }
    Unary(op, x) => {
      let sign = match op {
        Pos => "+"
        Neg => "-"
      }
      // `--` starts a comment: keep two minus signs apart.
      let gap = if (op is Neg && x.kind is Unary(Neg, _)) ||
        self.pending(x.span) {
        " "
      } else {
        ""
      }
      cat([Text(sign + gap), self.operand(x, 9)])
    }
    Binary(_, _, _)
    | And(_, _)
    | Or(_, _)
    | BoolTest(_, _, ..)
    | Like(_, ..)
    | Between(_, ..)
    | In(_, _, ..)
    | IsNull(_, ..)
    | IsMissing(_, ..)
    | IsType(_, _, ..)
    | Overlaps(_, _) => self.chain(e)
    Not(x) => spaced([Text("NOT"), self.operand(x, 3)])
    Case(operand~, branches~, default~) => {
      let head = match operand {
        Some(o) => cat([Text("CASE "), self.full(o)])
        None => Text("CASE")
      }
      let arms : Array[Doc] = []
      for b in branches {
        arms.push(Line)
        arms.push(
          spaced([Text("WHEN"), self.full(b.0), Text("THEN"), self.full(b.1)]),
        )
      }
      if default is Some(d) {
        arms.push(Line)
        arms.push(spaced([Text("ELSE"), self.full(d)]))
      }
      Group(cat([head, Nest(2, cat(arms)), Line, Text("END")]))
    }
    Cast(x, t) =>
      cat([Text("CAST("), self.full(x), Text(" AS " + type_text(t) + ")")])
    Extract(f, x) =>
      cat([Text("EXTRACT(" + field_text(f) + " FROM "), self.full(x), Text(")")])
    Trim(spec~, chars~, x) => {
      let words : Array[Doc] = []
      match spec {
        Some(Both) => words.push(Text("BOTH"))
        Some(Leading) => words.push(Text("LEADING"))
        Some(Trailing) => words.push(Text("TRAILING"))
        None => ()
      }
      if chars is Some(c) {
        words.push(self.full(c))
      }
      if !words.is_empty() {
        words.push(Text("FROM"))
      }
      words.push(self.full(x))
      cat([Text("TRIM("), spaced(words), Text(")")])
    }
    Substring(x, start~, length~) =>
      cat([
        Text("SUBSTRING("),
        self.full(x),
        Text(" FROM "),
        self.full(start),
        match length {
          Some(n) => cat([Text(" FOR "), self.full(n)])
          None => Nil
        },
        Text(")"),
      ])
    Position(a, b) =>
      cat([
        Text("POSITION("),
        self.operand(a, 6),
        Text(" IN "),
        self.full(b),
        Text(")"),
      ])
    Overlay(x, placing~, from~, for_~) =>
      cat([
        Text("OVERLAY("),
        self.full(x),
        Text(" PLACING "),
        self.full(placing),
        Text(" FROM "),
        self.full(from),
        match for_ {
          Some(n) => cat([Text(" FOR "), self.full(n)])
          None => Nil
        },
        Text(")"),
      ])
    Coalesce(xs) => bracketed("COALESCE(", self.items(xs), ")")
    NullIf(a, b) =>
      cat([Text("NULLIF("), self.full(a), Text(", "), self.full(b), Text(")")])
    DateAdd(f, a, b) =>
      cat([
        Text("DATE_ADD(" + field_text(f) + ", "),
        self.full(a),
        Text(", "),
        self.full(b),
        Text(")"),
      ])
    DateDiff(f, a, b) =>
      cat([
        Text("DATE_DIFF(" + field_text(f) + ", "),
        self.full(a),
        Text(", "),
        self.full(b),
        Text(")"),
      ])
    Call(name, args, quantifier~) => {
      let inner = match (args, quantifier) {
        // `f(SELECT ..)`: a lone subquery argument needs no own parentheses.
        ([{ kind: Query(sub), span, }], None) =>
          [cat([self.leading(span), self.query(sub)])]
        _ => self.items(args)
      }
      // The quantifier goes with the first argument, so that a broken call
      // has no space at the end of its first line.
      let q = match quantifier {
        Some(Distinct) => "DISTINCT "
        Some(All) => "ALL "
        None => ""
      }
      if q != "" && !inner.is_empty() {
        inner[0] = cat([Text(q), inner[0]])
      }
      bracketed(ident_text(name) + "(", inner, ")")
    }
    CallStar(name) => cat([ident_doc(name), Text("(*)")])
    List(xs) => bracketed("[", self.items(xs), "]")
    Bag(xs) => bracketed("<<", self.items(xs), ">>")
    Sexp(xs) => bracketed("SEXP(", self.items(xs), ")")
    Struct(fs) => bracketed("{", self.fields(fs), "}")
    Map(fs) => bracketed("MAP{", self.fields(fs), "}")
    Row(xs) =>
      // `(a)` reads as `a`, and `((SELECT ..), b)` as a subquery.
      if xs.length() >= 2 && !starts_with_query(xs[0]) && !self.row_calls {
        bracketed("(", self.items(xs), ")")
      } else {
        bracketed("ROW(", self.items(xs), ")")
      }
    Values(rows) => {
      let docs = rows.map(r => {
        match r.kind {
          Row(items) =>
            cat([self.leading(r.span), bracketed("(", self.items(items), ")")])
          _ => self.full(r)
        }
      })
      Group(cat([Text("VALUES"), Nest(2, cat([Line, break_items(docs)]))]))
    }
    Query(q) => sub(self.query(q))
    GraphMatch(m) => self.graph(m)
  }
}

///|
/// The left operand of a left-recursive form, and the level it needs.
fn left_operand(e : @ast.Expr) -> (@ast.Expr, Int)? {
  match e.kind {
    Or(a, _) => Some((a, 1))
    And(a, _) => Some((a, 2))
    BoolTest(a, _, ..) => Some((a, 4))
    Binary(op, a, _) => Some((a, binary_info(op).0))
    Like(a, ..)
    | Between(a, ..)
    | In(a, _, ..)
    | IsNull(a, ..)
    | IsMissing(a, ..)
    | IsType(a, _, ..)
    | Overlaps(a, _) => Some((a, 5))
    _ => None
  }
}

///|
/// Whether the left operand `a` of `parent` prints in parentheses.
fn left_needs_parens(a : @ast.Expr, min : Int, parent : @ast.Expr) -> Bool {
  // `x IS ARRAY < y` would read `ARRAY<` as an element type.
  let bare_array_before_lt = match parent.kind {
    Binary(Lt | Le | Ne, _, _) => a.kind is IsType(_, Array(None), ..)
    _ => false
  }
  level(a) < min || bare_array_before_lt
}

///|
/// A chain of left-recursive forms (`a AND b AND c`, `a + b + c`, `a IS NULL
/// IS NULL`), printed with a loop over the left spine: the parser builds
/// such chains without a depth limit.
fn Printer::chain(self : Printer, e : @ast.Expr) -> Doc {
  let spine = [e]
  let mut cur = e
  // The spine continues through operands of the same level only, so that
  // each level is its own group: `a > 1 AND b = 2` breaks before `AND`.
  while left_operand(cur) is Some((a, min)) &&
        !left_needs_parens(a, min, cur) &&
        left_operand(a) is Some(_) &&
        level(a) == level(cur) {
    spine.push(a)
    cur = a
  }
  let docs : Array[Doc] = []
  // All spine nodes start where the leftmost operand starts.
  for node in spine {
    docs.push(self.leading(node.span))
  }
  guard left_operand(cur) is Some((leaf, min)) else { return cat(docs) }
  docs.push(
    if left_needs_parens(leaf, min, cur) {
      cat([self.leading(leaf.span), parens(self.expr_body(leaf))])
    } else {
      self.expr(leaf)
    },
  )
  let suffixes : Array[Doc] = []
  for i = spine.length() - 1; i >= 0; i = i - 1 {
    suffixes.push(self.suffix(spine[i]))
  }
  docs.push(Nest(2, cat(suffixes)))
  Group(cat(docs))
}

///|
fn not_text(negated : Bool) -> String {
  if negated {
    " NOT"
  } else {
    ""
  }
}

///|
/// What follows the left operand of a left-recursive form.
fn Printer::suffix(self : Printer, e : @ast.Expr) -> Doc {
  match e.kind {
    Or(_, b) => cat([Line, Text("OR "), self.operand(b, 2)])
    And(_, b) => cat([Line, Text("AND "), self.operand(b, 3)])
    BoolTest(_, value, negated~) =>
      Text(
        " IS" +
        not_text(negated) +
        (match value {
          Some(true) => " TRUE"
          Some(false) => " FALSE"
          None => " UNKNOWN"
        }),
      )
    Binary(op, _, b) => {
      let (l, symbol) = binary_info(op)
      cat([Line, Text(symbol + " "), self.operand(b, l + 1)])
    }
    Like(_, pattern~, escape~, negated~) =>
      cat([
        Text(not_text(negated) + " LIKE "),
        self.operand(pattern, 6),
        match escape {
          Some(c) => cat([Text(" ESCAPE "), self.operand(c, 6)])
          None => Nil
        },
      ])
    Between(_, low~, high~, negated~) =>
      cat([
        Text(not_text(negated) + " BETWEEN "),
        self.operand(low, 6),
        Text(" AND "),
        self.operand(high, 6),
      ])
    In(_, b, negated~) => {
      let right = match b.kind {
        // `IN (e, ..)` is a row, also with one element.
        Row(items) if !(items.length() > 0 && starts_with_query(items[0])) =>
          cat([self.leading(b.span), bracketed("(", self.items(items), ")")])
        _ => self.operand(b, 6)
      }
      cat([Text(not_text(negated) + " IN "), right])
    }
    IsNull(_, negated~) => Text(" IS" + not_text(negated) + " NULL")
    IsMissing(_, negated~) => Text(" IS" + not_text(negated) + " MISSING")
    IsType(_, t, negated~) =>
      Text(" IS" + not_text(negated) + " " + type_text(t))
    Overlaps(_, b) => cat([Text(" OVERLAPS "), self.operand(b, 6)])
    _ => Nil
  }
}

///|
/// Whether `e` prints starting with a parenthesized query: `(SELECT ..)` or
/// `(VALUES ..)` as its leftmost part. The parser reads `((SELECT ..), b)`
/// as a subquery, so such a row prints as `ROW(..)`.
fn starts_with_query(e : @ast.Expr) -> Bool {
  let mut cur = e
  while true {
    match cur.kind {
      Query(_) | Values(_) => return true
      Path(a, _) => cur = a
      GraphMatch(m) => cur = m.graph
      _ =>
        match left_operand(cur) {
          Some((a, _)) => cur = a
          None => return false
        }
    }
  }
  false
}
