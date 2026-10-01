// FROM clauses: sources with AS/AT/BY, UNPIVOT, comma joins and explicit
// joins (including the Kotlin forms such as LEFT CROSS JOIN).

///|
fn from_span(f : @ast.FromItem) -> @ast.Span {
  match f {
    Scan(s) | Unpivot(s) => s.span
    Join(j) => j.span
  }
}

///|
fn Parser::from_clause(self : Parser) -> @ast.FromItem raise @ast.ParseError {
  let mut left = self.from_item()
  while self.eat_punct(',') {
    let right = self.from_item()
    left = Join({
      kind: Inner,
      form: Comma,
      left,
      right,
      span: from_span(left).merge(from_span(right)),
    })
  }
  left
}

///|
/// The join kind and form keywords at the cursor, if a join starts here.
fn Parser::join_keywords(
  self : Parser,
) -> (@ast.JoinKind, Bool)? raise @ast.ParseError {
  let kind : @ast.JoinKind? = if self.eat_word("INNER") {
    Some(Inner)
  } else if self.eat_word("LEFT") {
    ignore(self.eat_word("OUTER"))
    Some(Left)
  } else if self.eat_word("RIGHT") {
    ignore(self.eat_word("OUTER"))
    Some(Right)
  } else if self.eat_word("FULL") {
    ignore(self.eat_word("OUTER"))
    Some(Full)
  } else if self.at_word("OUTER") &&
    (self.at_word_at(1, "JOIN") || self.at_word_at(1, "CROSS")) {
    ignore(self.advance())
    Some(Full)
  } else {
    None
  }
  let cross = self.eat_word("CROSS")
  if self.eat_word("JOIN") {
    Some((kind.unwrap_or(Inner), cross))
  } else if kind is Some(_) || cross {
    raise self.error("expected JOIN")
  } else {
    None
  }
}

///|
fn Parser::from_item(self : Parser) -> @ast.FromItem raise @ast.ParseError {
  let mut left = self.from_base()
  while self.join_keywords() is Some((kind, cross)) {
    let right = self.from_base()
    let form : @ast.JoinForm = if cross {
      if self.at_word("ON") {
        self.fail("CROSS JOIN takes no ON condition")
      }
      Cross
    } else {
      self.expect_word("ON")
      On(self.expr())
    }
    left = Join({
      kind,
      form,
      left,
      right,
      span: from_span(left).merge(self.tokens[self.pos - 1].span),
    })
  }
  left
}

///|
/// A FROM source: a parenthesized join, `UNPIVOT expr`, or `expr`, with
/// aliases.
fn Parser::from_base(self : Parser) -> @ast.FromItem raise @ast.ParseError {
  if self.at_punct('(') && !self.at_query_start(1) {
    // A parenthesized join, such as `(b JOIN c ON x)`; otherwise the
    // parentheses belong to an expression.
    let saved = self.pos
    let saved_depth = self.depth
    ignore(self.advance())
    try self.nested(() => self.from_clause()) catch {
      _ => {
        self.pos = saved
        self.depth = saved_depth
      }
    } noraise {
      Join(_) as j if self.eat_punct(')') => return j
      _ => {
        self.pos = saved
        self.depth = saved_depth
      }
    }
  }
  let start = self.pos
  let lateral = self.eat_word("LATERAL")
  let unpivot = self.eat_word("UNPIVOT")
  let expr = self.expr()
  let as_ = self.as_alias()
  let at = if self.eat_word("AT") { Some(self.identifier()) } else { None }
  let by = if self.eat_word("BY") { Some(self.identifier()) } else { None }
  let source : @ast.FromSource = {
    lateral,
    expr,
    as_,
    at,
    by,
    span: self.span_from(start),
  }
  if unpivot {
    Unpivot(source)
  } else {
    Scan(source)
  }
}
