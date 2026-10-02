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
      let read = self.clause(
        () => {
          order_by.push(self.sort_spec())
          true
        },
        _ => false,
      )
      if !read || !self.eat_punct(',') {
        break
      }
    }
  }
  let limit = if self.eat_word("LIMIT") {
    Some(self.clause(() => self.expr(), error_expr))
  } else {
    None
  }
  let offset = if self.eat_word("OFFSET") {
    Some(self.clause(() => self.expr(), error_expr))
  } else {
    None
  }
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
  p.reject_unsupported()
  let q = p.query()
  ignore(p.eat_punct(';'))
  if !(p.peek().kind is End) {
    p.note("end of input")
    p.fail("unexpected input after the statement")
  }
  Query(q)
}

///|
/// Parses a script: statements separated by `;`, with the comments of the
/// source. Empty statements are skipped; a script may have no statements.
pub fn parse_script(source : String) -> @ast.Script raise @ast.ParseError {
  let (tokens, comments) = @lexer.lex_with_comments(source)
  let p = Parser::new(tokens)
  let statements : Array[@ast.Statement] = []
  while !(p.peek().kind is End) {
    if p.eat_punct(';') {
      continue
    }
    p.reject_unsupported()
    statements.push(Query(p.query()))
    if !(p.peek().kind is End) && !p.eat_punct(';') {
      p.note("end of input")
      p.fail("unexpected input after the statement")
    }
  }
  { statements, comments, span: { start: 0, end: source.length(), }, }
}

///|
/// Parses a script and recovers from errors (spec M3d): the partial script,
/// with `Error` nodes where the source is broken, and every error in source
/// order (at most 100).
pub fn parse_script_recovering(source : String) -> @ast.Recovered {
  let (tokens, comments, lex_errors) = @lexer.lex_recovering(source)
  let p = Parser::new(tokens)
  p.recovering = true
  p.lex_errors = lex_errors.length()
  for e in lex_errors {
    p.error_starts.add(error_span(e).start)
  }
  let statements : Array[@ast.Statement] = []
  while !(p.peek().kind is End) {
    if p.eat_punct(';') {
      continue
    }
    let start = p.pos
    let statement = p.recover(
      Statement,
      () => {
        p.reject_unsupported()
        let q = p.query()
        if !(p.peek().kind is End) && !p.eat_punct(';') {
          p.note("end of input")
          p.record(p.error("unexpected input after the statement"))
          p.skip_to(Statement)
        }
        @ast.Statement::Query(q)
      },
      span => @ast.Statement::Error(span),
    ) catch {
      _ => {
        // The error limit: the rest of the source is one error statement.
        let from = p.tokens[start].span.start
        statements.push(Error({ start: from, end: source.length(), }))
        break
      }
    }
    statements.push(statement)
  }
  {
    script: { statements, comments, span: { start: 0, end: source.length(), }, },
    errors: merge_errors(lex_errors, p.errors),
  }
}

///|
/// Two error lists, each in source order, merged by span start (stable:
/// at the same start, lexer errors come first).
fn merge_errors(
  a : Array[@ast.ParseError],
  b : Array[@ast.ParseError],
) -> Array[@ast.ParseError] {
  let out : Array[@ast.ParseError] = []
  let mut i = 0
  let mut j = 0
  while i < a.length() || j < b.length() {
    if j >= b.length() ||
      (i < a.length() && error_span(a[i]).start <= error_span(b[j]).start) {
      out.push(a[i])
      i += 1
    } else {
      out.push(b[j])
      j += 1
    }
  }
  out
}

///|
/// Statement kinds that later milestones parse (spec M3c §4.5).
let unsupported_statements : Array[String] = [
  "INSERT", "UPDATE", "DELETE", "REPLACE", "UPSERT", "REMOVE", "SET", "CREATE", "DROP",
  "EXEC", "EXPLAIN", "FROM",
]

///|
fn Parser::reject_unsupported(self : Parser) -> Unit raise @ast.ParseError {
  guard self.peek().kind is Word(w) else { return }
  let upper = w.to_upper()
  // A non-reserved word (such as REPLACE) is a statement keyword only before
  // INTO; otherwise it can be a variable.
  if unsupported_statements.contains(upper) &&
    !(self.peek_at(1).kind is Punct('(')) &&
    (is_reserved(w) || word_is(self.peek_at(1), "INTO")) {
    raise @ast.ParseError::Unsupported(
      message="\{upper} statements are not supported yet",
      span=self.peek().span,
    )
  }
}
