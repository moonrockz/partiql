// Primary expressions and path steps.

///|
fn Parser::postfix(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let base = self.primary()
  let steps : Array[@ast.PathStep] = []
  while true {
    if self.cont(() => self.at_punct('.')) {
      ignore(self.advance())
      let t = self.peek()
      if self.eat_punct('*') {
        steps.push(AllFields(t.span))
      } else if t.kind is StringLit(s) {
        ignore(self.advance())
        steps.push(FieldString(s, span=t.span))
      } else {
        steps.push(Field(self.identifier(allow_path_words=true)))
      }
    } else if self.cont(() => self.at_punct('[')) {
      let open = self.advance()
      if self.at_punct('*') && self.peek_at(1).kind is Punct(']') {
        ignore(self.advance())
        let close = self.advance()
        steps.push(AllElements(open.span.merge(close.span)))
      } else {
        let index = self.expr()
        self.expect_punct(']')
        steps.push(Index(index))
      }
    } else {
      break
    }
  }
  if steps.is_empty() {
    base
  } else {
    make(Path(base, steps), base.span.merge(self.tokens[self.pos - 1].span))
  }
}

///|
/// Words that start a special form when `(` follows.
let special_forms : Array[String] = [
  "CASE", "CAST", "EXTRACT", "TRIM", "SUBSTRING", "POSITION", "OVERLAY", "COALESCE",
  "NULLIF", "DATE_ADD", "DATE_DIFF",
]

///|
/// Words that start a query.
fn Parser::at_query_start(self : Parser, offset : Int) -> Bool {
  // `((SELECT ...) UNION ...)`: look through opening parentheses.
  let mut k = offset
  while self.peek_at(k).kind is Punct('(') {
    k += 1
  }
  let t = self.peek_at(k)
  word_is(t, "SELECT") ||
  word_is(t, "WITH") ||
  word_is(t, "PIVOT") ||
  word_is(t, "VALUES") ||
  word_is(t, "TABLE")
}

///|
fn Parser::literal(self : Parser, l : @ast.Literal) -> @ast.Expr {
  let t = self.advance()
  make(Lit(l), t.span)
}

///|
fn Parser::primary(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let t = self.peek()
  let start = self.pos
  match t.kind {
    IntLit(n) => self.literal(Int(n))
    DecimalLit(n) => self.literal(Decimal(n))
    FloatLit(n) => self.literal(Float(n))
    StringLit(s) => self.literal(String(s))
    IonLit(text, value) => self.literal(Ion(text, value))
    // The recovering lexer recorded the error.
    Invalid => {
      ignore(self.advance())
      error_expr(t.span)
    }
    QuotedIdent(_) => {
      let name = self.identifier()
      make(VarRef(name, qualified=false), name.span)
    }
    Punct('?') => {
      ignore(self.advance())
      make(Parameter, t.span)
    }
    Punct('@') => {
      ignore(self.advance())
      if self.peek().span.start != t.span.end {
        raise self.error("expected an identifier right after '@'")
      }
      let name = self.identifier()
      make(VarRef(name, qualified=true), t.span.merge(name.span))
    }
    Punct('[') => {
      ignore(self.advance())
      let items = self.expr_list(']')
      make(List(items), self.span_from(start))
    }
    Punct('{') => {
      ignore(self.advance())
      let fields = self.fields('}')
      make(Struct(fields), self.span_from(start))
    }
    Punct('<') if self.at_op("<<") => {
      ignore(self.advance())
      ignore(self.advance())
      let items : Array[@ast.Expr] = []
      if !self.eat_op(">>") {
        while true {
          items.push(self.item(() => self.expr()))
          if !self.list_next(">>") {
            break
          }
        }
      }
      make(Bag(items), self.span_from(start))
    }
    Punct('(') => self.parenthesized()
    Word(w) => self.word_primary(w)
    _ => {
      self.note("an expression")
      raise self.error("expected an expression")
    }
  }
}

///|
/// Comma-separated expressions up to `close` (consumed); may be empty.
fn Parser::expr_list(
  self : Parser,
  close : Char,
) -> Array[@ast.Expr] raise @ast.ParseError {
  let items : Array[@ast.Expr] = []
  if self.eat_punct(close) {
    return items
  }
  let closer = close.to_string()
  while true {
    items.push(self.item(() => self.expr()))
    if !self.list_next(closer) {
      break
    }
  }
  items
}

///|
/// `key: value` pairs up to `close` (consumed); may be empty.
fn Parser::fields(
  self : Parser,
  close : Char,
) -> Array[(@ast.Expr, @ast.Expr)] raise @ast.ParseError {
  let out : Array[(@ast.Expr, @ast.Expr)] = []
  if self.eat_punct(close) {
    return out
  }
  let closer = close.to_string()
  while true {
    out.push(
      self.recover(
        Item,
        () => {
          let key = self.expr()
          self.expect_punct(':')
          (key, self.expr())
        },
        span => (error_expr(span), error_expr(span)),
      ),
    )
    if !self.list_next(closer) {
      break
    }
  }
  out
}

///|
/// `(` ... `)`: a subquery, a row value, a graph MATCH,
/// or a parenthesized expression.
fn Parser::parenthesized(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let start = self.pos
  if self.at_query_start(1) {
    ignore(self.advance())
    let q = self.nested(() => self.query())
    if self.cont(() => self.at_word("MATCH")) {
      // A query operand is one parenthesized group, as Kotlin's exprPrimary.
      if !self.one_group(start + 1, self.pos) {
        raise self.error(
          "a query as the graph MATCH operand needs its own parentheses",
        )
      }
      return self.graph_match_rest(query_or_expr(q, q.span), start)
    }
    self.expect_punct(')')
    return query_or_expr(q, self.span_from(start))
  }
  ignore(self.advance())
  let first = self.expr()
  if self.cont(() => self.at_word("MATCH")) {
    return self.graph_match_rest(first, start)
  }
  if self.eat_punct(',') {
    let items = [first]
    items.append(self.expr_list(')'))
    return make(Row(items), self.span_from(start))
  }
  self.expect_punct(')')
  // A parenthesized query operand, such as `(SELECT ...) UNION ...`, is
  // handled by the query parser; here the parentheses only group.
  { ..first, span: self.span_from(start), }
}

///|
/// A query that is only an expression, such as `(SELECT 1) + 1` reached
/// through extra parentheses, is that expression, not a subquery.
fn query_or_expr(q : @ast.Query, span : @ast.Span) -> @ast.Expr {
  match q.body {
    Expr(e) if !has_clauses(q) => { ..e, span, }
    _ => make(Query(q), span)
  }
}

///|
fn Parser::word_primary(
  self : Parser,
  w : String,
) -> @ast.Expr raise @ast.ParseError {
  let t = self.peek()
  let start = self.pos
  let upper = w.to_upper()
  let next_is_open = self.peek_at(1).kind is Punct('(')
  match upper {
    "NULL" => return self.literal(Null)
    "MISSING" => return self.literal(Missing)
    "TRUE" => return self.literal(Bool(true))
    "FALSE" => return self.literal(Bool(false))
    "DATE" | "TIME" | "TIMESTAMP" | "INTERVAL" => return self.datetime_literal()
    _ => ()
  }
  if special_forms.contains(upper) && (next_is_open || upper == "CASE") {
    return self.special_form(upper)
  }
  if next_is_open &&
    (upper == "LIST" || upper == "SEXP" || upper == "BAG" || upper == "ROW") {
    ignore(self.advance())
    ignore(self.advance())
    let items = self.expr_list(')')
    let kind : @ast.ExprKind = match upper {
      "LIST" => List(items)
      "SEXP" => Sexp(items)
      "BAG" => Bag(items)
      _ => Row(items)
    }
    return make(kind, self.span_from(start))
  }
  if upper == "MAP" && self.peek_at(1).kind is Punct('{') {
    ignore(self.advance())
    ignore(self.advance())
    let fields = self.fields('}')
    return make(Map(fields), self.span_from(start))
  }
  if upper == "VALUES" {
    return self.values()
  }
  if next_is_open && !is_reserved(w) {
    return self.call()
  }
  // A reserved word that starts no expression: say what is missing.
  if is_reserved(w) {
    self.note("an expression")
    raise self.error("expected an expression")
  }
  let name = self.identifier()
  ignore(t)
  make(VarRef(name, qualified=false), name.span)
}

///|
/// `VALUES (..), (..)`: each row is a `Row`.
fn Parser::values(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let start = self.pos
  self.expect_word("VALUES")
  let rows : Array[@ast.Expr] = []
  while true {
    rows.push(
      self.item(() => {
        let row_start = self.pos
        self.expect_punct('(')
        let items = self.expr_list(')')
        make(Row(items), self.span_from(row_start))
      }),
    )
    if !self.eat_punct(',') {
      break
    }
  }
  make(Values(rows), self.span_from(start))
}

///|
/// `name(*)`, `name([ALL | DISTINCT] args)`, or `name(query)`.
fn Parser::call(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let start = self.pos
  let name = self.identifier()
  self.expect_punct('(')
  if self.at_punct('*') && self.peek_at(1).kind is Punct(')') {
    ignore(self.advance())
    ignore(self.advance())
    return make(CallStar(name), self.span_from(start))
  }
  if self.at_query_start(0) {
    let query_start = self.pos
    let q = self.nested(() => self.query())
    let arg = query_or_expr(q, self.span_from(query_start))
    self.expect_punct(')')
    return make(Call(name, [arg], quantifier=None), self.span_from(start))
  }
  let quantifier : @ast.SetQuantifier? = if self.eat_word("DISTINCT") {
    Some(Distinct)
  } else if self.eat_word("ALL") {
    Some(All)
  } else {
    None
  }
  let args = self.expr_list(')')
  if quantifier is Some(_) && args.is_empty() {
    self.fail("expected an argument")
  }
  make(Call(name, args, quantifier~), self.span_from(start))
}

///|
/// Whether the tokens from `from` up to `to` (exclusive) are one
/// parenthesized group: a `(` whose matching `)` is the last token.
fn Parser::one_group(self : Parser, from : Int, to : Int) -> Bool {
  guard to - from >= 2 && self.tokens[from].kind is Punct('(') else {
    return false
  }
  let mut depth = 0
  for i in from..<to {
    match self.tokens[i].kind {
      Punct('(') => depth += 1
      Punct(')') => {
        depth -= 1
        if depth == 0 {
          return i == to - 1
        }
      }
      _ => ()
    }
  }
  false
}
