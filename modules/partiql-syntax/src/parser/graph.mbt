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
  // No recovery inside patterns (spec M3d §4).
  let pattern = self.strictly(() => self.graph_pattern(many=true))
  self.expect_punct(')')
  let span = self.span_from(start)
  make(GraphMatch({ graph, pattern, span, }), span)
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
    self.note("a graph pattern")
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
  self.note("a label")
  raise self.error("expected a label")
}

///|
/// The restrictor that `token` names, if any. Quoted identifiers are never
/// restrictors.
fn restrictor_of(token : @lexer.Token) -> @ast.Restrictor? {
  match token.kind {
    Word(w) =>
      match w.to_upper() {
        "WALK" => Some(Walk)
        "TRAIL" => Some(Trail)
        "ACYCLIC" => Some(Acyclic)
        "SIMPLE" => Some(Simple)
        _ => None
      }
    _ => None
  }
}

///|
/// Whether the tokens `k` places ahead are `name =` (a path variable).
fn Parser::at_path_variable(self : Parser, k : Int) -> Bool {
  is_name(self.peek_at(k)) && self.peek_at(k + 1).kind is Punct('=')
}

///|
/// `ANY SHORTEST`, `ALL SHORTEST`, `ANY [k]`, `SHORTEST [k [GROUP]]`
/// (spec 7.5). `any = …` is a path variable, not a selector.
fn Parser::selector(self : Parser) -> @ast.Selector? raise @ast.ParseError {
  if self.at_path_variable(0) {
    return None
  }
  let start = self.pos
  let kind : @ast.SelectorKind = if self.at_word("ANY") &&
    self.at_word_at(1, "SHORTEST") {
    ignore(self.advance())
    ignore(self.advance())
    AnyShortest
  } else if self.eat_word("ALL") {
    self.expect_word("SHORTEST")
    AllShortest
  } else if self.eat_word("ANY") {
    let k = if self.peek().kind is IntLit(_) {
      Some(self.int_literal())
    } else {
      None
    }
    Any(k~)
  } else if self.eat_word("SHORTEST") {
    if self.peek().kind is IntLit(_) {
      let k = self.int_literal()
      ShortestK(k~, group=self.eat_word("GROUP"))
    } else {
      Shortest
    }
  } else {
    return None
  }
  Some({ kind, span: self.span_from(start), })
}

///|
/// Whether the `(` at the cursor starts a node: the next token is `)`, `:`
/// or WHERE, or a name followed by one of those (spec 7.6).
fn Parser::at_node(self : Parser) -> Bool {
  let closes = (t : @lexer.Token) => {
    t.kind is Punct(')' | ':') || word_is(t, "WHERE")
  }
  let next = self.peek_at(1)
  closes(next) || (is_name(next) && closes(self.peek_at(2)))
}

///|
/// `( path [WHERE expr] )` or `[ path [WHERE expr] ]`, with an optional
/// quantifier.
fn Parser::group(self : Parser) -> @ast.GroupPattern raise @ast.ParseError {
  let start = self.pos
  let (delimiter, close) : (@ast.GroupDelimiter, Char) = if self.eat_punct('(') {
    (Paren, ')')
  } else {
    self.expect_punct('[')
    (Bracket, ']')
  }
  let path = self.path_pattern()
  let where_ = if self.eat_word("WHERE") { Some(self.expr()) } else { None }
  self.expect_punct(close)
  let quantifier = self.quantifier()
  { delimiter, path, where_, quantifier, span: self.span_from(start), }
}

///|
/// `[selector] path (, path)* [WHERE expr]` when `many` (the parenthesized
/// form); `[selector] path` otherwise (the FROM form).
fn Parser::graph_pattern(
  self : Parser,
  many~ : Bool,
) -> @ast.GraphPattern raise @ast.ParseError {
  let start = self.pos
  let selector = self.selector()
  let paths = [self.path_pattern()]
  if many {
    while self.eat_punct(',') {
      paths.push(self.path_pattern())
    }
  }
  let where_ = if many && self.eat_word("WHERE") {
    Some(self.expr())
  } else {
    None
  }
  { selector, paths, where_, span: self.span_from(start), }
}

///|
/// `[restrictor] [name =] part+` (spec 7.4): a path variable first, then a
/// restrictor word that is followed by a part or a path variable.
fn Parser::path_pattern(
  self : Parser,
) -> @ast.PathPattern raise @ast.ParseError {
  let start = self.pos
  let restrictor = match restrictor_of(self.peek()) {
    Some(r) if !self.at_path_variable(0) &&
      (starts_part(self.peek_at(1)) || self.at_path_variable(1)) => {
      ignore(self.advance())
      Some(r)
    }
    _ => None
  }
  let variable = if self.at_path_variable(0) {
    let v = self.identifier()
    self.expect_punct('=')
    Some(v)
  } else {
    None
  }
  let parts : Array[@ast.PathPart] = []
  while starts_part(self.peek()) {
    parts.push(self.path_part())
  }
  if parts.is_empty() {
    self.note("a graph pattern")
    raise self.error("expected a node, edge or group pattern")
  }
  { restrictor, variable, parts, span: self.span_from(start), }
}

///|
fn Parser::path_part(self : Parser) -> @ast.PathPart raise @ast.ParseError {
  match self.peek().kind {
    Punct('(') if self.at_node() => Node(self.node())
    Punct('(' | '[') => Group(self.nested(() => self.group()))
    _ => Edge(self.edge())
  }
}
