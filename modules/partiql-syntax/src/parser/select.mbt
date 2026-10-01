// SELECT and PIVOT blocks.

///|
/// An alias: `AS name`, or a bare name that is not a reserved word.
fn Parser::as_alias(self : Parser) -> @ast.Identifier? raise @ast.ParseError {
  if self.eat_word("AS") {
    return Some(self.identifier())
  }
  match self.peek().kind {
    Word(w) if !is_reserved(w) => Some(self.identifier())
    QuotedIdent(_) => Some(self.identifier())
    _ => None
  }
}

///|
/// `expr.*` as a select item: a path whose last step is `.*`.
fn all_fields(e : @ast.Expr) -> @ast.Expr? {
  guard e.kind is Path(root, steps) && steps.last() is Some(AllFields(_)) else {
    return None
  }
  if steps.length() == 1 {
    Some(root)
  } else {
    Some({
      kind: Path(root, steps[:steps.length() - 1].to_owned()),
      span: e.span,
    })
  }
}

///|
fn Parser::projection(self : Parser) -> @ast.Projection raise @ast.ParseError {
  let t = self.peek()
  if self.eat_punct('*') {
    if self.at_punct(',') {
      self.fail("'*' must be the only select item")
    }
    return Star(t.span)
  }
  if self.eat_word("VALUE") {
    return Value(self.expr())
  }
  let items : Array[@ast.SelectItem] = []
  while true {
    let start = self.pos
    let e = self.expr()
    match all_fields(e) {
      Some(root) => items.push(AllFields(root, span=self.span_from(start)))
      None => {
        let as_ = self.as_alias()
        items.push(Expr(e, as_~, span=self.span_from(start)))
      }
    }
    if !self.eat_punct(',') {
      break
    }
  }
  Items(items)
}

///|
/// `SELECT [ALL | DISTINCT] projection` or `PIVOT value AT key`, then the
/// optional FROM, LET, WHERE, GROUP BY and HAVING clauses.
fn Parser::select(self : Parser) -> @ast.Select raise @ast.ParseError {
  let start = self.pos
  let (quantifier, projection) : (@ast.SetQuantifier?, @ast.Projection) = if self.eat_word(
      "PIVOT",
    ) {
    let value = self.expr()
    self.expect_word("AT")
    let key = self.expr()
    (None, Pivot(value~, key~))
  } else {
    self.expect_word("SELECT")
    let quantifier : @ast.SetQuantifier? = if self.eat_word("DISTINCT") {
      Some(Distinct)
    } else if self.eat_word("ALL") {
      Some(All)
    } else {
      None
    }
    (quantifier, self.projection())
  }
  let from = if self.eat_word("FROM") { Some(self.from_clause()) } else { None }
  if projection is Pivot(..) && from is None {
    self.fail("PIVOT needs FROM")
  }
  let let_ : Array[@ast.LetBinding] = []
  if self.eat_word("LET") {
    while true {
      let binding_start = self.pos
      let expr = self.expr()
      self.expect_word("AS")
      let name = self.identifier()
      let_.push({ expr, name, span: self.span_from(binding_start), })
      if !self.eat_punct(',') {
        break
      }
    }
  }
  let where_ = if self.eat_word("WHERE") { Some(self.expr()) } else { None }
  let group_by = if self.at_word("GROUP") && !self.at_word_at(1, "AS") {
    Some(self.group_by())
  } else {
    None
  }
  let having = if self.eat_word("HAVING") { Some(self.expr()) } else { None }
  {
    quantifier,
    projection,
    from,
    let_,
    where_,
    group_by,
    having,
    span: self.span_from(start),
  }
}

///|
fn Parser::group_by(self : Parser) -> @ast.GroupBy raise @ast.ParseError {
  let start = self.pos
  self.expect_word("GROUP")
  let partial = self.eat_word("PARTIAL")
  self.expect_word("BY")
  let keys : Array[@ast.GroupKey] = []
  while true {
    let key_start = self.pos
    let expr = self.expr()
    let as_ = if self.eat_word("AS") { Some(self.identifier()) } else { None }
    keys.push({ expr, as_, span: self.span_from(key_start), })
    if !self.eat_punct(',') {
      break
    }
  }
  let group_as = if self.at_word("GROUP") && self.at_word_at(1, "AS") {
    ignore(self.advance())
    ignore(self.advance())
    Some(self.identifier())
  } else {
    None
  }
  { partial, keys, group_as, span: self.span_from(start), }
}
