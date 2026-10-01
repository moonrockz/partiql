// Queries: WITH, set operations, ORDER BY, LIMIT, OFFSET; statements.

///|
fn single(body : @ast.QueryBody, span : @ast.Span) -> @ast.Query {
  { with_: [], body, order_by: [], limit: None, offset: None, span, }
}

///|
fn has_clauses(q : @ast.Query) -> Bool {
  !q.with_.is_empty() ||
  !q.order_by.is_empty() ||
  q.limit is Some(_) ||
  q.offset is Some(_)
}

///|
/// `[WITH ..] set_expr [ORDER BY ..] [LIMIT ..] [OFFSET ..]`
fn Parser::query(self : Parser) -> @ast.Query raise @ast.ParseError {
  let start = self.pos
  let with_ : Array[@ast.WithBinding] = []
  if self.eat_word("WITH") {
    while true {
      let binding_start = self.pos
      let name = self.identifier()
      self.expect_word("AS")
      self.expect_punct('(')
      let q = self.nested(() => self.query())
      self.expect_punct(')')
      with_.push({ name, query: q, span: self.span_from(binding_start), })
      if !self.eat_punct(',') {
        break
      }
    }
  }
  let body = self.set_expr()
  let order_by : Array[@ast.SortSpec] = []
  if self.eat_word("ORDER") {
    self.expect_word("BY")
    while true {
      order_by.push(self.sort_spec())
      if !self.eat_punct(',') {
        break
      }
    }
  }
  let limit = if self.eat_word("LIMIT") { Some(self.expr()) } else { None }
  let offset = if self.eat_word("OFFSET") { Some(self.expr()) } else { None }
  let clauses = !with_.is_empty() ||
    !order_by.is_empty() ||
    limit is Some(_) ||
    offset is Some(_)
  if !clauses {
    return body
  }
  // Clauses on a body that has its own clauses (a parenthesized query) wrap
  // it; otherwise they attach to the body.
  let inner = if has_clauses(body) {
    single(Expr(make(Query(body), body.span)), body.span)
  } else {
    body
  }
  { ..inner, with_, order_by, limit, offset, span: self.span_from(start), }
}

///|
fn Parser::sort_spec(self : Parser) -> @ast.SortSpec raise @ast.ParseError {
  let start = self.pos
  let expr = self.expr()
  let order : @ast.SortOrder? = if self.eat_word("ASC") {
    Some(Asc)
  } else if self.eat_word("DESC") {
    Some(Desc)
  } else {
    None
  }
  let nulls : @ast.NullsOrder? = if self.eat_word("NULLS") {
    if self.eat_word("FIRST") {
      Some(First)
    } else if self.eat_word("LAST") {
      Some(Last)
    } else {
      raise self.error("expected FIRST or LAST")
    }
  } else {
    None
  }
  { expr, order, nulls, span: self.span_from(start), }
}

///|
/// The set operator at the cursor among `ops`, with its OUTER flag and
/// quantifier.
fn Parser::set_operator(
  self : Parser,
  ops : Array[(String, @ast.SetOpKind)],
) -> (@ast.SetOpKind, Bool, @ast.SetQuantifier?, @ast.Corresponding?)? raise @ast.ParseError {
  let outer = self.at_word("OUTER")
  let offset = if outer { 1 } else { 0 }
  for pair in ops {
    if self.at_word_at(offset, pair.0) {
      for _ in 0..<=offset {
        ignore(self.advance())
      }
      let quantifier : @ast.SetQuantifier? = if self.eat_word("ALL") {
        Some(All)
      } else if self.eat_word("DISTINCT") {
        Some(Distinct)
      } else {
        None
      }
      let corresponding : @ast.Corresponding? = if self.eat_word(
          "CORRESPONDING",
        ) {
        if self.eat_word("BY") {
          self.expect_punct('(')
          let names = [self.identifier()]
          while self.eat_punct(',') {
            names.push(self.identifier())
          }
          self.expect_punct(')')
          Some(By(names))
        } else {
          Some(All)
        }
      } else {
        None
      }
      return Some((pair.1, outer, quantifier, corresponding))
    }
    self.note(pair.0)
  }
  None
}

///|
fn set_op(
  op : (@ast.SetOpKind, Bool, @ast.SetQuantifier?, @ast.Corresponding?),
  left : @ast.Query,
  right : @ast.Query,
) -> @ast.Query {
  let span = left.span.merge(right.span)
  single(
    SetOp({
      op: op.0,
      outer: op.1,
      quantifier: op.2,
      corresponding: op.3,
      left,
      right,
      span,
    }),
    span,
  )
}

///|
/// UNION and EXCEPT, left associative, below INTERSECT.
fn Parser::set_expr(self : Parser) -> @ast.Query raise @ast.ParseError {
  let mut left = self.set_term()
  while self.set_operator([("UNION", Union), ("EXCEPT", Except)]) is Some(op) {
    let right = self.set_term()
    left = set_op(op, left, right)
  }
  left
}

///|
fn Parser::set_term(self : Parser) -> @ast.Query raise @ast.ParseError {
  let mut left = self.set_primary()
  while self.set_operator([("INTERSECT", Intersect)]) is Some(op) {
    let right = self.set_primary()
    left = set_op(op, left, right)
  }
  left
}

///|
/// A SELECT or PIVOT block, or an expression (which includes a
/// parenthesized query and VALUES).
fn Parser::set_primary(self : Parser) -> @ast.Query raise @ast.ParseError {
  if self.at_word("TABLE") {
    let start = self.pos
    ignore(self.advance())
    let name = [self.identifier()]
    while self.eat_punct('.') {
      name.push(self.identifier(allow_path_words=true))
    }
    return single(Table(name), self.span_from(start))
  }
  if self.at_word("SELECT") || self.at_word("PIVOT") {
    let s = self.select()
    return single(Select(s), s.span)
  }
  let e = self.expr()
  match e.kind {
    Query(q) => { ..q, span: e.span, }
    _ => single(Expr(e), e.span)
  }
}

///|
/// Parses one statement from `source`: a query with an optional final `;`.
pub fn parse_statement(source : String) -> @ast.Statement raise @ast.ParseError {
  let p = Parser::new(@lexer.lex(source))
  let q = p.query()
  ignore(p.eat_punct(';'))
  if !(p.peek().kind is End) {
    p.note("end of input")
    p.fail("unexpected input after the statement")
  }
  Query(q)
}
