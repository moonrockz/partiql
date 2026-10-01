// Special forms: CASE and the SQL functions with keyword arguments.

///|
fn Parser::special_form(
  self : Parser,
  name : String,
) -> @ast.Expr raise @ast.ParseError {
  let start = self.pos
  ignore(self.advance())
  if name == "CASE" {
    return self.case_expr(start)
  }
  self.expect_punct('(')
  let kind : @ast.ExprKind = match name {
    "CAST" => {
      let value = self.expr()
      self.expect_word("AS")
      Cast(value, self.data_type())
    }
    "EXTRACT" => {
      let field = self.datetime_field()
      self.expect_word("FROM")
      Extract(field, self.expr())
    }
    "TRIM" => self.trim_args()
    "SUBSTRING" => {
      let value = self.expr()
      if self.eat_word("FROM") {
        let start_at = self.expr()
        let length = if self.eat_word("FOR") { Some(self.expr()) } else { None }
        Substring(value, start=start_at, length~)
      } else {
        self.expect_punct(',')
        let start_at = self.expr()
        let length = if self.eat_punct(',') { Some(self.expr()) } else { None }
        Substring(value, start=start_at, length~)
      }
    }
    "POSITION" => {
      // The needle stops before IN, which would otherwise be a predicate.
      let needle = self.concat()
      if !self.eat_word("IN") {
        self.expect_punct(',')
      }
      Position(needle, self.expr())
    }
    "OVERLAY" => {
      let value = self.expr()
      if self.eat_word("PLACING") {
        let placing = self.expr()
        self.expect_word("FROM")
        let from = self.expr()
        let for_ = if self.eat_word("FOR") { Some(self.expr()) } else { None }
        Overlay(value, placing~, from~, for_~)
      } else {
        self.expect_punct(',')
        let placing = self.expr()
        self.expect_punct(',')
        let from = self.expr()
        let for_ = if self.eat_punct(',') { Some(self.expr()) } else { None }
        Overlay(value, placing~, from~, for_~)
      }
    }
    "COALESCE" => {
      let args = self.expr_list(')')
      if args.is_empty() {
        self.fail("COALESCE needs at least one argument")
      }
      return make(Coalesce(args), self.span_from(start))
    }
    "NULLIF" => {
      let a = self.expr()
      self.expect_punct(',')
      NullIf(a, self.expr())
    }
    "DATE_ADD" | "DATE_DIFF" => {
      let field = self.datetime_field()
      self.expect_punct(',')
      let a = self.expr()
      self.expect_punct(',')
      let b = self.expr()
      if name == "DATE_ADD" {
        DateAdd(field, a, b)
      } else {
        DateDiff(field, a, b)
      }
    }
    _ => raise self.error("unknown special form \{name}")
  }
  self.expect_punct(')')
  make(kind, self.span_from(start))
}

///|
/// `TRIM([BOTH | LEADING | TRAILING] [chars] FROM value)` or `TRIM(value)`;
/// the opening parenthesis is consumed.
fn Parser::trim_args(self : Parser) -> @ast.ExprKind raise @ast.ParseError {
  let spec : @ast.TrimSpec? = if self.eat_word("BOTH") {
    Some(Both)
  } else if self.eat_word("LEADING") {
    Some(Leading)
  } else if self.eat_word("TRAILING") {
    Some(Trailing)
  } else {
    None
  }
  if spec is Some(_) {
    if self.eat_word("FROM") {
      return Trim(spec~, chars=None, self.expr())
    }
    let chars = self.expr()
    self.expect_word("FROM")
    return Trim(spec~, chars=Some(chars), self.expr())
  }
  let first = self.expr()
  if self.eat_word("FROM") {
    Trim(spec=None, chars=Some(first), self.expr())
  } else {
    Trim(spec=None, chars=None, first)
  }
}

///|
/// `CASE [operand] WHEN .. THEN .. {WHEN .. THEN ..} [ELSE ..] END`; the
/// CASE word is consumed.
fn Parser::case_expr(
  self : Parser,
  start : Int,
) -> @ast.Expr raise @ast.ParseError {
  let operand = if self.at_word("WHEN") { None } else { Some(self.expr()) }
  let branches : Array[(@ast.Expr, @ast.Expr)] = []
  while self.eat_word("WHEN") {
    let condition = self.expr()
    self.expect_word("THEN")
    branches.push((condition, self.expr()))
  }
  if branches.is_empty() {
    self.fail("expected WHEN")
  }
  let default = if self.eat_word("ELSE") { Some(self.expr()) } else { None }
  self.expect_word("END")
  make(Case(operand~, branches~, default~), self.span_from(start))
}
