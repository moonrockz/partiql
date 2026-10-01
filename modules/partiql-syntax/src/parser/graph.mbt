// Graph pattern matching (GPML): RFC 0033 and the Kotlin gpml rules
// (spec M2b sections 6 and 7).

///|
/// Whether `token` can be an identifier: a non-reserved word or a quoted
/// identifier.
fn is_name(token : @lexer.Token) -> Bool {
  match token.kind {
    Word(w) => !is_reserved(w)
    QuotedIdent(_) => true
    _ => false
  }
}

///|
/// Whether `token` can start a path part: a node or group `(`, a group `[`,
/// or an edge (`-`, `<`, `~`).
fn starts_part(token : @lexer.Token) -> Bool {
  token.kind is Punct('(' | '[' | '-' | '<' | '~')
}

///|
/// After `( graph`: `MATCH pattern )`. `start` is the token index of `(`.
fn Parser::graph_match_rest(
  self : Parser,
  graph : @ast.Expr,
  start : Int,
) -> @ast.Expr raise @ast.ParseError {
  self.expect_word("MATCH")
  let pattern = self.graph_pattern(many=true)
  self.expect_punct(')')
  let span = self.span_from(start)
  make(GraphMatch({ graph, pattern, span, }), span)
}

///|
/// `path (, path)* [WHERE expr]` when `many`; one path otherwise (the FROM
/// form). Task 3 adds the selector.
fn Parser::graph_pattern(
  self : Parser,
  many~ : Bool,
) -> @ast.GraphPattern raise @ast.ParseError {
  let start = self.pos
  let paths = [self.path_pattern()]
  ignore(many)
  { selector: None, paths, where_: None, span: self.span_from(start), }
}

///|
/// `part+`. Task 3 adds the restrictor and the path variable.
fn Parser::path_pattern(
  self : Parser,
) -> @ast.PathPattern raise @ast.ParseError {
  let start = self.pos
  let parts : Array[@ast.PathPart] = []
  while starts_part(self.peek()) {
    parts.push(self.path_part())
  }
  if parts.is_empty() {
    self.note("graph pattern")
    raise self.error("expected a node, edge or group pattern")
  }
  { restrictor: None, variable: None, parts, span: self.span_from(start), }
}

///|
/// A node or an edge. Task 3 adds groups.
fn Parser::path_part(self : Parser) -> @ast.PathPart raise @ast.ParseError {
  if self.at_punct('(') {
    Node(self.node())
  } else {
    Edge(self.edge())
  }
}

///|
/// The inside of a node or an edge filler: `[name] [: label] [WHERE expr]`.
fn Parser::element_body(
  self : Parser,
) -> (@ast.Identifier?, @ast.Label?, @ast.Expr?) raise @ast.ParseError {
  let variable = if is_name(self.peek()) {
    Some(self.identifier())
  } else {
    None
  }
  let label = if self.eat_punct(':') { Some(self.label()) } else { None }
  let where_ = if self.eat_word("WHERE") { Some(self.expr()) } else { None }
  (variable, label, where_)
}

///|
/// `( [name] [: label] [WHERE expr] )`
fn Parser::node(self : Parser) -> @ast.NodePattern raise @ast.ParseError {
  let start = self.pos
  self.expect_punct('(')
  let (variable, label, where_) = self.element_body()
  self.expect_punct(')')
  { variable, label, where_, span: self.span_from(start), }
}

///|
/// An edge, full (`-[e:L]->`) or abbreviated (`->`), with an optional
/// quantifier. The characters need not touch (spec 7.7).
fn Parser::edge(self : Parser) -> @ast.EdgePattern raise @ast.ParseError {
  let start = self.pos
  let left = self.eat_punct('<')
  let line = if self.eat_punct('-') {
    '-'
  } else if self.eat_punct('~') {
    '~'
  } else {
    self.note("graph pattern")
    raise self.error("expected a node, edge or group pattern")
  }
  let filler : @ast.EdgeFiller? = if self.at_punct('[') {
    let filler_start = self.pos
    ignore(self.advance())
    let (variable, label, where_) = self.element_body()
    self.expect_punct(']')
    let span = self.span_from(filler_start)
    self.expect_punct(line)
    Some({ variable, label, where_, span, })
  } else {
    None
  }
  let right = self.eat_punct('>')
  let direction : @ast.EdgeDirection = match (left, line, right) {
    (true, '-', false) => Left
    (false, '~', false) => Undirected
    (false, '-', true) => Right
    (true, '~', false) => LeftOrUndirected
    (false, '~', true) => UndirectedOrRight
    (true, '-', true) => LeftOrRight
    (false, '-', false) => Any
    _ => raise self.error("'<~' cannot end with '>'")
  }
  let quantifier = self.quantifier()
  { direction, filler, quantifier, span: self.span_from(start), }
}

///|
/// `+`, `*`, `{m,}` or `{m,n}` when present.
fn Parser::quantifier(self : Parser) -> @ast.Quantifier? raise @ast.ParseError {
  let start = self.pos
  let kind : @ast.QuantifierKind = if self.eat_punct('+') {
    Plus
  } else if self.eat_punct('*') {
    Star
  } else if self.eat_punct('{') {
    let lower = self.int_literal()
    self.expect_punct(',')
    let upper = if self.at_punct('}') { None } else { Some(self.int_literal()) }
    if upper is Some(u) && u < lower {
      raise self.error("the upper bound is less than the lower bound")
    }
    self.expect_punct('}')
    Range(lower~, upper~)
  } else {
    return None
  }
  Some({ kind, span: self.span_from(start), })
}

///|
/// `term (| term)*`: `!` binds tighter than `&`, `&` tighter than `|`; both
/// binary operators are left associative (spec 7.9).
fn Parser::label(self : Parser) -> @ast.Label raise @ast.ParseError {
  let start = self.pos
  let mut left = self.label_term()
  while self.eat_punct('|') {
    let right = self.label_term()
    left = { kind: Or(left, right), span: self.span_from(start), }
  }
  left
}

///|
fn Parser::label_term(self : Parser) -> @ast.Label raise @ast.ParseError {
  let start = self.pos
  let mut left = self.label_factor()
  while self.eat_punct('&') {
    let right = self.label_factor()
    left = { kind: And(left, right), span: self.span_from(start), }
  }
  left
}

///|
/// `!primary` or `primary`; `!!A` is an error, `!(!A)` is not.
fn Parser::label_factor(self : Parser) -> @ast.Label raise @ast.ParseError {
  let start = self.pos
  if self.eat_punct('!') {
    let x = self.label_primary()
    { kind: Not(x), span: self.span_from(start), }
  } else {
    self.label_primary()
  }
}

///|
/// A name, `%`, or `( label )`.
fn Parser::label_primary(self : Parser) -> @ast.Label raise @ast.ParseError {
  let start = self.pos
  if self.eat_punct('%') {
    return { kind: Wildcard, span: self.span_from(start), }
  }
  if self.eat_punct('(') {
    let inner = self.nested(() => self.label())
    self.expect_punct(')')
    return { ..inner, span: self.span_from(start), }
  }
  if is_name(self.peek()) {
    let name = self.identifier()
    return { kind: Name(name), span: name.span, }
  }
  self.note("label")
  raise self.error("expected a label")
}
