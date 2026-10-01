// Test support: a compact rendering of syntax tree shapes, without spans.

///|
fn ident_shape(i : @ast.Identifier) -> String {
  if i.delimited {
    "\"\{i.text}\""
  } else {
    i.text
  }
}

///|
fn field_shape(f : @ast.DatetimeField) -> String {
  match f {
    Year => "year"
    Month => "month"
    Day => "day"
    Hour => "hour"
    Minute => "minute"
    Second => "second"
    TimezoneHour => "timezone_hour"
    TimezoneMinute => "timezone_minute"
  }
}

///|
fn qualifier_shape(q : @ast.IntervalQualifier) -> String {
  let p = match (q.start_precision, q.fractional_precision) {
    (Some(a), Some(b)) => "(\{a},\{b})"
    (Some(a), None) => "(\{a})"
    _ => ""
  }
  match q.end {
    Some(e) => "\{field_shape(q.start)}\{p} to \{field_shape(e)}"
    None => "\{field_shape(q.start)}\{p}"
  }
}

///|
fn opt_int(n : Int?) -> String {
  match n {
    Some(v) => "(\{v})"
    None => ""
  }
}

///|
fn type_shape(t : @ast.DataType) -> String {
  match t {
    Null => "NULL"
    Missing => "MISSING"
    Bool => "BOOL"
    TinyInt => "TINYINT"
    SmallInt => "SMALLINT"
    Int => "INT"
    BigInt => "BIGINT"
    Decimal(p, s) =>
      match (p, s) {
        (Some(a), Some(b)) => "DECIMAL(\{a},\{b})"
        _ => "DECIMAL\{opt_int(p)}"
      }
    Numeric(p, s) =>
      match (p, s) {
        (Some(a), Some(b)) => "NUMERIC(\{a},\{b})"
        _ => "NUMERIC\{opt_int(p)}"
      }
    Real => "REAL"
    Double(p) => "DOUBLE\{opt_int(p)}"
    Char(n) => "CHAR\{opt_int(n)}"
    Varchar(n) => "VARCHAR\{opt_int(n)}"
    String => "STRING"
    Symbol => "SYMBOL"
    Blob => "BLOB"
    Clob => "CLOB"
    Date => "DATE"
    Time(p, with_tz~) => "TIME\{opt_int(p)}\{if with_tz { " TZ" } else { "" }}"
    Timestamp(p, with_tz~) =>
      "TIMESTAMP\{opt_int(p)}\{if with_tz { " TZ" } else { "" }}"
    Interval(q) => "INTERVAL \{qualifier_shape(q)}"
    Struct => "STRUCT"
    Tuple => "TUPLE"
    List => "LIST"
    Bag => "BAG"
    Sexp => "SEXP"
    Any => "ANY"
    Map(k, v) => "MAP<\{type_shape(k)},\{type_shape(v)}>"
    Array(Some(e)) => "ARRAY<\{type_shape(e)}>"
    Array(None) => "ARRAY"
    Custom(i) => ident_shape(i)
  }
}

///|
fn literal_shape(l : @ast.Literal) -> String {
  match l {
    Null => "null"
    Missing => "missing"
    Bool(b) => "\{b}"
    Int(t) | Decimal(t) | Float(t) => t
    String(s) => "'\{s}'"
    Ion(t, _) => "`\{t}`"
    Date(s) => "(date '\{s}')"
    Time(s, precision~, with_tz~) =>
      "(time\{opt_int(precision)}\{if with_tz { " tz" } else { "" }} '\{s}')"
    Timestamp(s, precision~, with_tz~) =>
      "(timestamp\{opt_int(precision)}\{if with_tz { " tz" } else { "" }} '\{s}')"
    Interval(s, negative~, qualifier~) =>
      "(interval \{if negative { "-" } else { "" }}'\{s}' \{qualifier_shape(qualifier)})"
  }
}

///|
fn binary_shape(op : @ast.BinaryOp) -> String {
  match op {
    Add => "+"
    Sub => "-"
    Mul => "*"
    Div => "/"
    Mod => "%"
    Concat => "||"
    Eq => "="
    Ne => "<>"
    Lt => "<"
    Le => "<="
    Gt => ">"
    Ge => ">="
  }
}

///|
fn quantifier_prefix(q : @ast.SetQuantifier?) -> String {
  match q {
    Some(All) => "all "
    Some(Distinct) => "distinct "
    None => ""
  }
}

///|
fn not_prefix(negated : Bool, name : String) -> String {
  if negated {
    "not-\{name}"
  } else {
    name
  }
}

///|
fn shape(e : @ast.Expr) -> String {
  match e.kind {
    Lit(l) => literal_shape(l)
    VarRef(i, qualified~) =>
      if qualified {
        "@\{ident_shape(i)}"
      } else {
        ident_shape(i)
      }
    Parameter => "?"
    Path(root, steps) => {
      let parts = steps.map(step => {
        match step {
          Field(i) => ".\{ident_shape(i)}"
          FieldString(s, ..) => ".'\{s}'"
          Index(x) => "[\{shape(x)}]"
          AllElements(_) => "[*]"
          AllFields(_) => ".*"
        }
      })
      "(path \{shape(root)} \{parts.join(" ")})"
    }
    Unary(Pos, x) => "(pos \{shape(x)})"
    Unary(Neg, x) => "(neg \{shape(x)})"
    Binary(op, a, b) => "(\{binary_shape(op)} \{shape(a)} \{shape(b)})"
    And(a, b) => "(and \{shape(a)} \{shape(b)})"
    Or(a, b) => "(or \{shape(a)} \{shape(b)})"
    Not(a) => "(not \{shape(a)})"
    BoolTest(x, value, negated~) => {
      let v = match value {
        Some(true) => "true"
        Some(false) => "false"
        None => "unknown"
      }
      "(\{not_prefix(negated, "is")}-\{v} \{shape(x)})"
    }
    Like(x, pattern~, escape~, negated~) =>
      match escape {
        Some(esc) =>
          "(\{not_prefix(negated, "like")} \{shape(x)} \{shape(pattern)} \{shape(esc)})"
        None => "(\{not_prefix(negated, "like")} \{shape(x)} \{shape(pattern)})"
      }
    Between(x, low~, high~, negated~) =>
      "(\{not_prefix(negated, "between")} \{shape(x)} \{shape(low)} \{shape(high)})"
    In(a, b, negated~) =>
      "(\{not_prefix(negated, "in")} \{shape(a)} \{shape(b)})"
    IsNull(x, negated~) => "(\{not_prefix(negated, "is")}-null \{shape(x)})"
    IsMissing(x, negated~) =>
      "(\{not_prefix(negated, "is")}-missing \{shape(x)})"
    IsType(x, t, negated~) =>
      "(\{not_prefix(negated, "is")} \{shape(x)} \{type_shape(t)})"
    Overlaps(a, b) => "(overlaps \{shape(a)} \{shape(b)})"
    Case(operand~, branches~, default~) => {
      let parts : Array[String] = []
      if operand is Some(o) {
        parts.push(shape(o))
      }
      for b in branches {
        parts.push("(when \{shape(b.0)} \{shape(b.1)})")
      }
      if default is Some(d) {
        parts.push("(else \{shape(d)})")
      }
      "(case \{parts.join(" ")})"
    }
    Cast(x, t) => "(cast \{shape(x)} \{type_shape(t)})"
    Extract(f, x) => "(extract \{field_shape(f)} \{shape(x)})"
    Trim(spec~, chars~, x) => {
      let parts : Array[String] = []
      match spec {
        Some(Both) => parts.push("both")
        Some(Leading) => parts.push("leading")
        Some(Trailing) => parts.push("trailing")
        None => ()
      }
      if chars is Some(c) {
        parts.push(shape(c))
      }
      parts.push(shape(x))
      "(trim \{parts.join(" ")})"
    }
    Substring(x, start~, length~) =>
      match length {
        Some(n) => "(substring \{shape(x)} \{shape(start)} \{shape(n)})"
        None => "(substring \{shape(x)} \{shape(start)})"
      }
    Position(a, b) => "(position \{shape(a)} \{shape(b)})"
    Overlay(x, placing~, from~, for_~) =>
      match for_ {
        Some(n) =>
          "(overlay \{shape(x)} \{shape(placing)} \{shape(from)} \{shape(n)})"
        None => "(overlay \{shape(x)} \{shape(placing)} \{shape(from)})"
      }
    Coalesce(xs) => "(coalesce \{xs.map(shape).join(" ")})"
    NullIf(a, b) => "(nullif \{shape(a)} \{shape(b)})"
    DateAdd(f, a, b) => "(date_add \{field_shape(f)} \{shape(a)} \{shape(b)})"
    DateDiff(f, a, b) => "(date_diff \{field_shape(f)} \{shape(a)} \{shape(b)})"
    Call(name, args, quantifier~) =>
      if args.is_empty() && quantifier is None {
        "(call \{ident_shape(name)})"
      } else {
        "(call \{ident_shape(name)} \{quantifier_prefix(quantifier)}\{args.map(shape).join(" ")})"
      }
    CallStar(name) => "(call \{ident_shape(name)} *)"
    List(xs) => "[\{xs.map(shape).join(" ")}]"
    Bag(xs) => "<<\{xs.map(shape).join(" ")}>>"
    Sexp(xs) => "(sexp \{xs.map(shape).join(" ")})"
    Struct(fs) => "{\{fs.map(f => "\{shape(f.0)}:\{shape(f.1)}").join(" ")}}"
    Map(fs) => "(map \{fs.map(f => "\{shape(f.0)}:\{shape(f.1)}").join(" ")})"
    Row(xs) => "(row \{xs.map(shape).join(" ")})"
    Values(xs) => "(values \{xs.map(shape).join(" ")})"
    Query(q) => query_shape(q)
  }
}

///|
fn expr_shape(source : String) -> String raise {
  shape(@parser.parse_expression(source))
}

///|
fn syntax_error(e : Error) -> Bool {
  e is @ast.ParseError::Syntax(_)
}
