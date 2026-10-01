// Expressions: the precedence ladder of the Kotlin grammar, lowest first:
// OR, AND, NOT, IS [NOT] TRUE|FALSE|UNKNOWN, predicates (comparisons, IS,
// IN, LIKE, BETWEEN, OVERLAPS; left associative), ||, + -, * / %, unary
// signs, path steps.

///|
fn make(kind : @ast.ExprKind, span : @ast.Span) -> @ast.Expr {
  { kind, span, }
}

///|
fn spanning(a : @ast.Expr, b : @ast.Expr) -> @ast.Span {
  a.span.merge(b.span)
}

///|
fn Parser::expr(self : Parser) -> @ast.Expr raise @ast.ParseError {
  self.nested(() => self.or_expr())
}

///|
fn Parser::or_expr(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let mut left = self.and_expr()
  while self.eat_word("OR") {
    let right = self.and_expr()
    left = make(Or(left, right), spanning(left, right))
  }
  left
}

///|
fn Parser::and_expr(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let mut left = self.not_expr()
  while self.eat_word("AND") {
    let right = self.not_expr()
    left = make(And(left, right), spanning(left, right))
  }
  left
}

///|
fn Parser::not_expr(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let start = self.pos
  if self.eat_word("NOT") {
    let operand = self.nested(() => self.not_expr())
    return make(Not(operand), self.span_from(start))
  }
  self.bool_test()
}

///|
/// The truth value after `IS [NOT]`, when the IS starts a boolean test.
fn Parser::bool_test_value(self : Parser, offset : Int) -> Bool?? {
  let t = self.peek_at(offset)
  if word_is(t, "TRUE") {
    Some(Some(true))
  } else if word_is(t, "FALSE") {
    Some(Some(false))
  } else if word_is(t, "UNKNOWN") {
    Some(None)
  } else {
    None
  }
}

///|
fn Parser::bool_test(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let mut operand = self.predicate()
  while self.at_word("IS") {
    let negated = self.at_word_at(1, "NOT")
    let offset = if negated { 2 } else { 1 }
    guard self.bool_test_value(offset) is Some(value) else { break }
    for _ in 0..<=offset {
      ignore(self.advance())
    }
    operand = make(
      BoolTest(operand, value, negated~),
      operand.span.merge(self.tokens[self.pos - 1].span),
    )
  }
  operand
}

///|
fn Parser::comparison_op(self : Parser) -> @ast.BinaryOp? {
  // `>>` closes a bag and `<<` opens one; neither is a comparison.
  if self.at_op(">>") || self.at_op("<<") {
    return None
  }
  let ops : Array[(String, @ast.BinaryOp)] = [
    ("<=", Le),
    (">=", Ge),
    ("<>", Ne),
    ("!=", Ne),
    ("=", Eq),
    ("<", Lt),
    (">", Gt),
  ]
  for pair in ops {
    if self.eat_op(pair.0) {
      return Some(pair.1)
    }
  }
  None
}

///|
fn Parser::predicate(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let mut left = self.concat()
  while true {
    if self.comparison_op() is Some(op) {
      let right = self.concat()
      left = make(Binary(op, left, right), spanning(left, right))
      continue
    }
    if self.at_word("IS") {
      let negated = self.at_word_at(1, "NOT")
      let offset = if negated { 2 } else { 1 }
      if self.bool_test_value(offset) is Some(_) {
        break
      }
      ignore(self.advance())
      if negated {
        ignore(self.advance())
      }
      let kind : @ast.ExprKind = if self.eat_word("NULL") {
        IsNull(left, negated~)
      } else if self.eat_word("MISSING") {
        IsMissing(left, negated~)
      } else {
        IsType(left, self.data_type(), negated~)
      }
      left = make(kind, left.span.merge(self.tokens[self.pos - 1].span))
      continue
    }
    let negated = self.at_word("NOT") &&
      (
        self.at_word_at(1, "IN") ||
        self.at_word_at(1, "LIKE") ||
        self.at_word_at(1, "BETWEEN")
      )
    if negated {
      ignore(self.advance())
    }
    if self.eat_word("IN") {
      // `IN (e, ..)` is a row even with one element (Kotlin's IN '(' expr ')'
      // alternative): `x IN (5)` and `x IN 5` differ. A subquery stays a
      // subquery.
      let right = if self.at_punct('(') && !self.at_query_start(1) {
        let start = self.pos
        ignore(self.advance())
        let items = self.expr_list(')')
        if items.is_empty() {
          self.fail("expected an expression")
        }
        make(Row(items), self.span_from(start))
      } else {
        self.concat()
      }
      left = make(In(left, right, negated~), spanning(left, right))
    } else if self.eat_word("LIKE") {
      let pattern = self.concat()
      let escape = if self.eat_word("ESCAPE") {
        Some(self.concat())
      } else {
        None
      }
      let end = match escape {
        Some(e) => e.span
        None => pattern.span
      }
      left = make(Like(left, pattern~, escape~, negated~), left.span.merge(end))
    } else if self.eat_word("BETWEEN") {
      let low = self.concat()
      self.expect_word("AND")
      let high = self.concat()
      left = make(Between(left, low~, high~, negated~), spanning(left, high))
    } else if negated {
      self.fail("expected IN, LIKE or BETWEEN")
    } else if self.eat_word("OVERLAPS") {
      let right = self.concat()
      left = make(Overlaps(left, right), spanning(left, right))
    } else {
      break
    }
  }
  left
}

///|
fn Parser::concat(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let mut left = self.additive()
  while self.eat_op("||") {
    let right = self.additive()
    left = make(Binary(Concat, left, right), spanning(left, right))
  }
  left
}

///|
fn Parser::additive(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let mut left = self.multiplicative()
  while true {
    let op : @ast.BinaryOp = if self.eat_punct('+') {
      Add
    } else if self.eat_punct('-') {
      Sub
    } else {
      break
    }
    let right = self.multiplicative()
    left = make(Binary(op, left, right), spanning(left, right))
  }
  left
}

///|
fn Parser::multiplicative(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let mut left = self.unary()
  while true {
    let op : @ast.BinaryOp = if self.eat_punct('*') {
      Mul
    } else if self.eat_punct('/') {
      Div
    } else if self.eat_punct('%') {
      Mod
    } else {
      break
    }
    let right = self.unary()
    left = make(Binary(op, left, right), spanning(left, right))
  }
  left
}

///|
fn Parser::unary(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let start = self.pos
  let op : @ast.UnaryOp? = if self.eat_punct('+') {
    Some(Pos)
  } else if self.eat_punct('-') {
    Some(Neg)
  } else {
    None
  }
  match op {
    Some(o) => {
      let operand = self.nested(() => self.unary())
      make(Unary(o, operand), self.span_from(start))
    }
    None => self.postfix()
  }
}

///|
/// Parses one expression from `source`. The whole input must be the
/// expression.
pub fn parse_expression(source : String) -> @ast.Expr raise @ast.ParseError {
  let p = Parser::new(@lexer.lex(source))
  let e = p.expr()
  if !(p.peek().kind is End) {
    p.note("end of input")
    p.fail("unexpected input after the expression")
  }
  e
}
