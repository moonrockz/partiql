// Names, literals and types in canonical spelling.

///|
/// `s` between `q` quotes, with each `q` inside doubled.
fn quote(s : String, q : Char) -> String {
  let buf = StringBuilder()
  buf.write_char(q)
  for c in s {
    if c == q {
      buf.write_char(q)
    }
    buf.write_char(c)
  }
  buf.write_char(q)
  buf.to_string()
}

///|
/// A delimited identifier stays quoted (it is case-sensitive); a regular one
/// prints as written.
fn ident_text(i : @ast.Identifier) -> String {
  if i.delimited {
    quote(i.text, '"')
  } else {
    i.text
  }
}

///|
fn ident_doc(i : @ast.Identifier) -> Doc {
  Text(ident_text(i))
}

///|
fn field_text(f : @ast.DatetimeField) -> String {
  match f {
    Year => "YEAR"
    Month => "MONTH"
    Day => "DAY"
    Hour => "HOUR"
    Minute => "MINUTE"
    Second => "SECOND"
    TimezoneHour => "TIMEZONE_HOUR"
    TimezoneMinute => "TIMEZONE_MINUTE"
  }
}

///|
fn precision_text(p : Int?) -> String {
  match p {
    Some(n) => "(\{n})"
    None => ""
  }
}

///|
fn qualifier_text(q : @ast.IntervalQualifier) -> String {
  let start = field_text(q.start)
  match q.end {
    None =>
      match (q.start_precision, q.fractional_precision) {
        (Some(p), Some(f)) => "\{start}(\{p}, \{f})"
        (p, _) => start + precision_text(p)
      }
    Some(end) =>
      start +
      precision_text(q.start_precision) +
      " TO " +
      field_text(end) +
      precision_text(q.fractional_precision)
  }
}

///|
fn time_zone_text(with_tz : Bool) -> String {
  if with_tz {
    " WITH TIME ZONE"
  } else {
    ""
  }
}

///|
fn literal_doc(l : @ast.Literal) -> Doc {
  Text(
    match l {
      Null => "NULL"
      Missing => "MISSING"
      Bool(true) => "TRUE"
      Bool(false) => "FALSE"
      Int(t) | Decimal(t) | Float(t) => t
      String(s) => quote(s, '\'')
      Ion(t, _) => "`" + t + "`"
      Date(t) => "DATE " + quote(t, '\'')
      Time(t, precision~, with_tz~) =>
        "TIME" +
        precision_text(precision) +
        time_zone_text(with_tz) +
        " " +
        quote(t, '\'')
      Timestamp(t, precision~, with_tz~) =>
        "TIMESTAMP" +
        precision_text(precision) +
        time_zone_text(with_tz) +
        " " +
        quote(t, '\'')
      Interval(t, negative~, qualifier~) =>
        "INTERVAL " +
        (if negative { "-" } else { "" }) +
        quote(t, '\'') +
        " " +
        qualifier_text(qualifier)
    },
  )
}

///|
fn type_text(t : @ast.DataType) -> String {
  match t {
    Null => "NULL"
    Missing => "MISSING"
    Bool => "BOOL"
    TinyInt => "TINYINT"
    SmallInt => "SMALLINT"
    Int => "INT"
    BigInt => "BIGINT"
    Decimal(p, s) => "DECIMAL" + scale_text(p, s)
    Numeric(p, s) => "NUMERIC" + scale_text(p, s)
    Real => "REAL"
    Double(None) => "DOUBLE PRECISION"
    Double(Some(p)) => "FLOAT(\{p})"
    Char(n) => "CHAR" + precision_text(n)
    Varchar(n) => "VARCHAR" + precision_text(n)
    String => "STRING"
    Symbol => "SYMBOL"
    Blob => "BLOB"
    Clob => "CLOB"
    Date => "DATE"
    Time(p, with_tz~) => "TIME" + precision_text(p) + time_zone_text(with_tz)
    Timestamp(p, with_tz~) =>
      "TIMESTAMP" + precision_text(p) + time_zone_text(with_tz)
    Interval(q) => "INTERVAL " + qualifier_text(q)
    Struct => "STRUCT"
    Tuple => "TUPLE"
    List => "LIST"
    Bag => "BAG"
    Sexp => "SEXP"
    Any => "ANY"
    Map(k, v) => "MAP<\{type_text(k)}, \{type_text(v)}>"
    Array(None) => "ARRAY"
    Array(Some(e)) => "ARRAY<\{type_text(e)}>"
    Custom(i) => if i.delimited { quote(i.text, '"') } else { i.text }
  }
}

///|
fn scale_text(p : Int?, s : Int?) -> String {
  match (p, s) {
    (Some(a), Some(b)) => "(\{a}, \{b})"
    (a, _) => precision_text(a)
  }
}
