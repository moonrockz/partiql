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
fn Printer::list(self : Printer, xs : Array[@ast.Expr]) -> Doc {
  sep(xs.map(x => self.full(x)), ", ")
}

///|
fn Printer::fields(self : Printer, fs : Array[(@ast.Expr, @ast.Expr)]) -> Doc {
  sep(fs.map(f => cat([self.full(f.0), Text(": "), self.full(f.1)])), ", ")
}

///|
fn negated_word(negated : Bool) -> Doc {
  if negated {
    Text("NOT")
  } else {
    Nil
  }
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
    Binary(op, a, b) => {
      let (l, symbol) = binary_info(op)
      // `x IS ARRAY < y` would read `ARRAY<` as an element type.
      let left = if symbol.has_prefix("<") &&
        a.kind is IsType(_, Array(None), ..) {
        cat([self.leading(a.span), parens(self.expr_body(a))])
      } else {
        self.operand(a, l)
      }
      spaced([left, Text(symbol), self.operand(b, l + 1)])
    }
    And(a, b) => spaced([self.operand(a, 2), Text("AND"), self.operand(b, 3)])
    Or(a, b) => spaced([self.operand(a, 1), Text("OR"), self.operand(b, 2)])
    Not(x) => spaced([Text("NOT"), self.operand(x, 3)])
    BoolTest(x, value, negated~) =>
      spaced([
        self.operand(x, 4),
        Text("IS"),
        negated_word(negated),
        Text(
          match value {
            Some(true) => "TRUE"
            Some(false) => "FALSE"
            None => "UNKNOWN"
          },
        ),
      ])
    Like(x, pattern~, escape~, negated~) =>
      spaced([
        self.operand(x, 5),
        negated_word(negated),
        Text("LIKE"),
        self.operand(pattern, 6),
        match escape {
          Some(c) => spaced([Text("ESCAPE"), self.operand(c, 6)])
          None => Nil
        },
      ])
    Between(x, low~, high~, negated~) =>
      spaced([
        self.operand(x, 5),
        negated_word(negated),
        Text("BETWEEN"),
        self.operand(low, 6),
        Text("AND"),
        self.operand(high, 6),
      ])
    In(a, b, negated~) => {
      let right = match b.kind {
        // `IN (e, ..)` is a row, also with one element.
        Row(items) => cat([self.leading(b.span), parens(self.list(items))])
        _ => self.operand(b, 6)
      }
      spaced([self.operand(a, 5), negated_word(negated), Text("IN"), right])
    }
    IsNull(x, negated~) =>
      spaced([
        self.operand(x, 5),
        Text("IS"),
        negated_word(negated),
        Text("NULL"),
      ])
    IsMissing(x, negated~) =>
      spaced([
        self.operand(x, 5),
        Text("IS"),
        negated_word(negated),
        Text("MISSING"),
      ])
    IsType(x, t, negated~) =>
      spaced([
        self.operand(x, 5),
        Text("IS"),
        negated_word(negated),
        Text(type_text(t)),
      ])
    Overlaps(a, b) =>
      spaced([self.operand(a, 5), Text("OVERLAPS"), self.operand(b, 6)])
    Case(operand~, branches~, default~) => {
      let words : Array[Doc] = [Text("CASE")]
      if operand is Some(o) {
        words.push(self.full(o))
      }
      for b in branches {
        words.push(
          spaced([Text("WHEN"), self.full(b.0), Text("THEN"), self.full(b.1)]),
        )
      }
      if default is Some(d) {
        words.push(spaced([Text("ELSE"), self.full(d)]))
      }
      words.push(Text("END"))
      spaced(words)
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
    Coalesce(xs) => cat([Text("COALESCE("), self.list(xs), Text(")")])
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
      let q = match quantifier {
        Some(Distinct) => Text("DISTINCT ")
        Some(All) => Text("ALL ")
        None => Nil
      }
      let inner = match (args, quantifier) {
        // `f(SELECT ..)`: a lone subquery argument needs no own parentheses.
        ([{ kind: Query(sub), span, }], None) =>
          cat([self.leading(span), self.query(sub)])
        _ => self.list(args)
      }
      cat([ident_doc(name), Text("("), q, inner, Text(")")])
    }
    CallStar(name) => cat([ident_doc(name), Text("(*)")])
    List(xs) => cat([Text("["), self.list(xs), Text("]")])
    Bag(xs) => cat([Text("<<"), self.list(xs), Text(">>")])
    Sexp(xs) => cat([Text("SEXP("), self.list(xs), Text(")")])
    Struct(fs) => cat([Text("{"), self.fields(fs), Text("}")])
    Map(fs) => cat([Text("MAP{"), self.fields(fs), Text("}")])
    Row(xs) =>
      if xs.length() >= 2 {
        parens(self.list(xs))
      } else {
        cat([Text("ROW("), self.list(xs), Text(")")])
      }
    Values(rows) => {
      let docs = rows.map(r => {
        match r.kind {
          Row(items) => cat([self.leading(r.span), parens(self.list(items))])
          _ => self.full(r)
        }
      })
      cat([Text("VALUES "), sep(docs, ", ")])
    }
    Query(q) => parens(self.query(q))
    GraphMatch(m) => self.graph(m)
  }
}
