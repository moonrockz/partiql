// Data types (CAST targets, IS types) and interval qualifiers.

///|
fn Parser::int_literal(self : Parser) -> Int raise @ast.ParseError {
  match self.peek().kind {
    IntLit(n) => {
      ignore(self.advance())
      @string.parse_int(n) catch {
        _ => raise self.error("number is too large")
      }
    }
    _ => {
      self.note("an integer")
      raise self.error("expected an integer")
    }
  }
}

///|
/// `( n )` when present.
fn Parser::precision(self : Parser) -> Int? raise @ast.ParseError {
  if self.eat_punct('(') {
    let n = self.int_literal()
    self.expect_punct(')')
    Some(n)
  } else {
    None
  }
}

///|
/// `( p [, s] )` when present.
fn Parser::precision_scale(self : Parser) -> (Int?, Int?) raise @ast.ParseError {
  if self.eat_punct('(') {
    let p = self.int_literal()
    let s = if self.eat_punct(',') { Some(self.int_literal()) } else { None }
    self.expect_punct(')')
    (Some(p), s)
  } else {
    (None, None)
  }
}

///|
/// `WITH TIME ZONE` (true), `WITHOUT TIME ZONE` (false), or nothing (false).
fn Parser::time_zone(self : Parser) -> Bool raise @ast.ParseError {
  if self.eat_word("WITH") {
    self.expect_word("TIME")
    self.expect_word("ZONE")
    true
  } else if self.eat_word("WITHOUT") {
    self.expect_word("TIME")
    self.expect_word("ZONE")
    false
  } else {
    false
  }
}

///|
/// A datetime field word: YEAR .. SECOND, TIMEZONE_HOUR, TIMEZONE_MINUTE.
fn Parser::datetime_field(
  self : Parser,
) -> @ast.DatetimeField raise @ast.ParseError {
  let fields : Array[(String, @ast.DatetimeField)] = [
    ("YEAR", Year),
    ("MONTH", Month),
    ("DAY", Day),
    ("HOUR", Hour),
    ("MINUTE", Minute),
    ("SECOND", Second),
    ("TIMEZONE_HOUR", TimezoneHour),
    ("TIMEZONE_MINUTE", TimezoneMinute),
  ]
  for pair in fields {
    if self.eat_word(pair.0) {
      return pair.1
    }
  }
  raise self.error("expected a datetime field")
}

///|
/// `field [(p [, s])] [TO field [(p)]]`
fn Parser::interval_qualifier(
  self : Parser,
) -> @ast.IntervalQualifier raise @ast.ParseError {
  let start = self.datetime_field()
  let (start_precision, fractional_precision) = self.precision_scale()
  if self.eat_word("TO") {
    let end = self.datetime_field()
    let end_precision = self.precision()
    {
      start,
      start_precision,
      end: Some(end),
      fractional_precision: match end_precision {
        Some(p) => Some(p)
        None => fractional_precision
      },
    }
  } else {
    { start, start_precision, end: None, fractional_precision, }
  }
}

///|
fn Parser::data_type(self : Parser) -> @ast.DataType raise @ast.ParseError {
  let t = self.peek()
  guard t.kind is Word(w) else {
    if t.kind is QuotedIdent(_) {
      return Custom(self.identifier())
    }
    self.note("a type")
    raise self.error("expected a type")
  }
  let upper = w.to_upper()
  let simple : @ast.DataType? = match upper {
    "NULL" => Some(Null)
    "MISSING" => Some(Missing)
    "BOOL" | "BOOLEAN" => Some(Bool)
    "TINYINT" => Some(TinyInt)
    "SMALLINT" | "INT2" | "INTEGER2" => Some(SmallInt)
    "INT" | "INTEGER" | "INT4" | "INTEGER4" => Some(Int)
    "BIGINT" | "INT8" | "INTEGER8" => Some(BigInt)
    "REAL" => Some(Real)
    "STRING" => Some(String)
    "SYMBOL" => Some(Symbol)
    "BLOB" => Some(Blob)
    "CLOB" => Some(Clob)
    "DATE" => Some(Date)
    "STRUCT" => Some(Struct)
    "TUPLE" => Some(Tuple)
    "LIST" => Some(List)
    "BAG" => Some(Bag)
    "SEXP" => Some(Sexp)
    "ANY" => Some(Any)
    _ => None
  }
  if simple is Some(s) {
    ignore(self.advance())
    return s
  }
  match upper {
    "DECIMAL" | "DEC" | "NUMERIC" => {
      ignore(self.advance())
      let (p, s) = self.precision_scale()
      if upper == "NUMERIC" {
        Numeric(p, s)
      } else {
        Decimal(p, s)
      }
    }
    "DOUBLE" => {
      ignore(self.advance())
      self.expect_word("PRECISION")
      Double(None)
    }
    "FLOAT" => {
      ignore(self.advance())
      Double(self.precision())
    }
    "CHAR" | "CHARACTER" => {
      ignore(self.advance())
      if self.eat_word("VARYING") {
        Varchar(self.precision())
      } else {
        Char(self.precision())
      }
    }
    "VARCHAR" => {
      ignore(self.advance())
      Varchar(self.precision())
    }
    "TIME" | "TIMESTAMP" => {
      ignore(self.advance())
      let p = self.precision()
      let with_tz = self.time_zone()
      if upper == "TIME" {
        Time(p, with_tz~)
      } else {
        Timestamp(p, with_tz~)
      }
    }
    "INTERVAL" => {
      ignore(self.advance())
      Interval(self.interval_qualifier())
    }
    "MAP" => {
      ignore(self.advance())
      self.expect_punct('<')
      let k = self.nested(() => self.data_type())
      self.expect_punct(',')
      let v = self.nested(() => self.data_type())
      self.expect_punct('>')
      Map(k, v)
    }
    "ARRAY" => {
      ignore(self.advance())
      if self.eat_punct('<') {
        let e = self.nested(() => self.data_type())
        self.expect_punct('>')
        Array(Some(e))
      } else {
        Array(None)
      }
    }
    _ => {
      if is_reserved(w) {
        self.note("a type")
        raise self.error("expected a type")
      }
      Custom(self.identifier())
    }
  }
}
