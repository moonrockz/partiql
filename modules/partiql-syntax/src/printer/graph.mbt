// Graph MATCH: always the parenthesized form (spec M3a section 6).

///|
fn label_level(l : @ast.Label) -> Int {
  match l.kind {
    Or(_, _) => 1
    And(_, _) => 2
    Not(_) => 3
    Name(_) | Wildcard => 4
  }
}

///|
/// `!` binds tighter than `&`, `&` tighter than `|`; both binary operators
/// are left associative; `!` applies to a primary.
fn label_doc(l : @ast.Label, min : Int) -> Doc {
  let body = match l.kind {
    Name(i) => ident_doc(i)
    Wildcard => Text("%")
    Not(x) => cat([Text("!"), label_doc(x, 4)])
    And(a, b) => cat([label_doc(a, 2), Text("&"), label_doc(b, 3)])
    Or(a, b) => cat([label_doc(a, 1), Text("|"), label_doc(b, 2)])
  }
  if label_level(l) < min {
    parens(body)
  } else {
    body
  }
}

///|
fn quantifier_doc(q : @ast.Quantifier?) -> Doc {
  match q {
    None => Nil
    Some({ kind: Plus, .. }) => Text("+")
    Some({ kind: Star, .. }) => Text("*")
    Some({ kind: Range(lower~, upper=Some(u)), .. }) => Text("{\{lower},\{u}}")
    Some({ kind: Range(lower~, upper=None), .. }) => Text("{\{lower},}")
  }
}

///|
/// `[name] [:label] [WHERE expr]` inside a node or an edge filler.
fn Printer::element(
  self : Printer,
  variable : @ast.Identifier?,
  label : @ast.Label?,
  where_ : @ast.Expr?,
) -> Doc {
  let head = cat([
    match variable {
      Some(v) => ident_doc(v)
      None => Nil
    },
    match label {
      Some(l) => cat([Text(":"), label_doc(l, 1)])
      None => Nil
    },
  ])
  match where_ {
    Some(w) => spaced([head, Text("WHERE"), self.full(w)])
    None => head
  }
}

///|
/// Full-form opening and closing, and the abbreviated form.
fn edge_tokens(d : @ast.EdgeDirection) -> (String, String, String) {
  match d {
    Left => ("<-", "-", "<-")
    Undirected => ("~", "~", "~")
    Right => ("-", "->", "->")
    LeftOrUndirected => ("<~", "~", "<~")
    UndirectedOrRight => ("~", "~>", "~>")
    LeftOrRight => ("<-", "->", "<->")
    Any => ("-", "-", "-")
  }
}

///|
fn Printer::part(self : Printer, p : @ast.PathPart) -> Doc {
  match p {
    Node(n) =>
      cat([
        self.leading(n.span),
        Text("("),
        self.element(n.variable, n.label, n.where_),
        Text(")"),
      ])
    Edge(e) => {
      let (open, close, abbreviated) = edge_tokens(e.direction)
      let body = match e.filler {
        Some(f) =>
          cat([
            Text(open + "["),
            self.element(f.variable, f.label, f.where_),
            Text("]" + close),
          ])
        None => Text(abbreviated)
      }
      cat([self.leading(e.span), body, quantifier_doc(e.quantifier)])
    }
    Group(g) => {
      let (open, close) = match g.delimiter {
        Paren => ("(", ")")
        Bracket => ("[", "]")
      }
      let where_ = match g.where_ {
        Some(w) => cat([Text(" WHERE "), self.full(w)])
        None => Nil
      }
      cat([
        self.leading(g.span),
        Text(open),
        self.path_pattern(g.path),
        where_,
        Text(close),
        quantifier_doc(g.quantifier),
      ])
    }
  }
}

///|
fn Printer::path_pattern(self : Printer, p : @ast.PathPattern) -> Doc {
  let lead = self.leading(p.span)
  let words : Array[Doc] = []
  match p.restrictor {
    Some(Walk) => words.push(Text("WALK"))
    Some(Trail) => words.push(Text("TRAIL"))
    Some(Acyclic) => words.push(Text("ACYCLIC"))
    Some(Simple) => words.push(Text("SIMPLE"))
    None => ()
  }
  if p.variable is Some(v) {
    words.push(cat([ident_doc(v), Text(" =")]))
  }
  for part in p.parts {
    words.push(self.part(part))
  }
  cat([lead, spaced(words)])
}

///|
fn selector_doc(s : @ast.Selector) -> Doc {
  Text(
    match s.kind {
      AnyShortest => "ANY SHORTEST"
      AllShortest => "ALL SHORTEST"
      Shortest => "SHORTEST"
      Any(k=None) => "ANY"
      Any(k=Some(k)) => "ANY \{k}"
      ShortestK(k~, group~) =>
        if group {
          "SHORTEST \{k} GROUP"
        } else {
          "SHORTEST \{k}"
        }
    },
  )
}

///|
fn Printer::graph(self : Printer, m : @ast.GraphMatch) -> Doc {
  let words : Array[Doc] = [self.full(m.graph), Text("MATCH")]
  if m.pattern.selector is Some(s) {
    words.push(selector_doc(s))
  }
  words.push(sep(m.pattern.paths.map(p => self.path_pattern(p)), ", "))
  if m.pattern.where_ is Some(w) {
    words.push(Text("WHERE"))
    words.push(self.full(w))
  }
  parens(spaced(words))
}
