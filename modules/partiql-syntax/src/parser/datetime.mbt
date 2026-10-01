// DATE, TIME, TIMESTAMP and INTERVAL literals.

///|
fn Parser::string_literal(self : Parser) -> String raise @ast.ParseError {
  match self.peek().kind {
    StringLit(s) => {
      ignore(self.advance())
      s
    }
    _ => {
      self.note("string")
      raise self.error("expected a string")
    }
  }
}

///|
fn Parser::datetime_literal(self : Parser) -> @ast.Expr raise @ast.ParseError {
  let start = self.pos
  let word = match self.advance().kind {
    Word(w) => w.to_upper()
    _ => ""
  }
  let literal : @ast.Literal = match word {
    "DATE" => Date(self.string_literal())
    "TIME" | "TIMESTAMP" => {
      let precision = self.precision()
      let with_tz = self.time_zone()
      let text = self.string_literal()
      if word == "TIME" {
        Time(text, precision~, with_tz~)
      } else {
        Timestamp(text, precision~, with_tz~)
      }
    }
    _ => {
      let negative = if self.eat_punct('-') {
        true
      } else {
        ignore(self.eat_punct('+'))
        false
      }
      let text = self.string_literal()
      Interval(text, negative~, qualifier=self.interval_qualifier())
    }
  }
  make(Lit(literal), self.span_from(start))
}
