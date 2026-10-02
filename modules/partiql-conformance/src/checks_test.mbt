///|
test "syntax check treats Unsupported as failure" {
  // Nothing raises Unsupported since M2b; a stub parser stands in for a
  // statement that a later milestone parses.
  let unsupported : (String) -> @syntax.Statement raise @syntax.ParseError = _ => {
    raise @syntax.ParseError::Unsupported(
      message="DML",
      span=({ start: 0, end: 6, } : @syntax.Span),
    )
  }
  let dml = "INSERT INTO t VALUE 1"
  @expect.expect_all(soft => {
    soft
    .expect(check_syntax(true, dml, parse=unsupported) is Fail(_))
    .to_be_true()
    soft
    .expect(check_syntax(false, dml, parse=unsupported) is Fail(_))
    .to_be_true()
    soft
    .expect(check_syntax(true, "SELECT * FROM (g MATCH (x))"))
    .to_equal(Pass)
    soft.expect(check_syntax(true, "SELECT a FROM t")).to_equal(Pass)
    soft.expect(check_syntax(false, "SELECT FROM t")).to_equal(Pass)
  })
}

///|
test "codec check accepts symbols and legacy forms" {
  @expect.expect_all(soft => {
    for
      text in [
        "{id: Enterprise}", "$date::2021-08-22", "$time::\"04:05:06\"", "$bag::[1, $missing::null]",
      ] {
      soft.expect(check_codec(@text.read_ion(text)), label=text).to_equal(Pass)
    }
  })
}

///|
test "codec check fails malformed values" {
  @expect.expect_all(soft => {
    soft.expect(check_codec(@text.read_ion("foo::1")) is Fail(_)).to_be_true()
    soft.expect(check_codec(@text.read_ion("(1 2)")) is Fail(_)).to_be_true()
  })
}

///|
test "ion payloads are found in document order and round-trip" {
  @expect.expect_all(soft => {
    let x = @text.read_ion("{a: $ion::null.int, b: [$ion::x::(1 2)]}")
    let payloads = ion_payloads(x)
    soft.expect(payloads.length()).to_equal(2)
    for p in payloads {
      soft.expect(check_ion_roundtrip(p)).to_equal(Pass)
    }
  })
}

///|
enum Outcome {
  Pass
  Fail(String)
  NotApplicable
} derive(Debug, Eq)

///|
/// `expect_success` is true for SyntaxSuccess and false for SyntaxFail.
fn check_syntax(
  expect_success : Bool,
  statement : String,
  parse? : (String) -> @syntax.Statement raise @syntax.ParseError = @syntax.parse,
) -> Outcome {
  try parse(statement) catch {
    Unsupported(message~, ..) => Fail("unsupported: \{message}")
    Syntax(message~, ..) =>
      if expect_success {
        Fail("syntax error: \{message}")
      } else {
        Pass
      }
  } noraise {
    _ =>
      if expect_success {
        Pass
      } else {
        Fail("parsed, but a syntax error was expected")
      }
  }
}

///|
/// Evaluation tests use only valid statements, so they must all parse.
fn check_parses(statement : String) -> Outcome {
  check_syntax(true, statement)
}

///|
/// Decode, re-encode and re-decode: the value must be stable, and encoding
/// must be a fixpoint (spec M1 section 6.1).
fn check_codec(x : @ion.IonValue) -> Outcome {
  try {
    let v = @partiql_ion.from_ion(x)
    let once = @partiql_ion.to_ion(v)
    let v2 = @partiql_ion.from_ion(once)
    if v2 != v {
      Fail("decode(encode(v)) differs from v")
    } else if !@partiql_ion.to_ion(v2).equals(once) {
      Fail("encoding is not a fixpoint")
    } else {
      Pass
    }
  } catch {
    Unsupported(reason) => Fail("unsupported: \{reason}")
    Malformed(reason) => Fail("malformed: \{reason}")
  }
}

///|
/// Every `$ion`-annotated value inside `x`, in document order.
fn ion_payloads(x : @ion.IonValue) -> Array[@ion.IonValue] {
  let out : Array[@ion.IonValue] = []
  fn walk(v : @ion.IonValue) -> Unit {
    if v.annotations().get(0).bind(token => token.text()) == Some("$ion") {
      out.push(v)
      return
    }
    match v.kind() {
      List(items) | Sexp(items) =>
        for item in items {
          walk(item)
        }
      Struct(fields) =>
        for field in fields {
          walk(field.value())
        }
      _ => ()
    }
  }
  walk(x)
  out
}

///|
fn check_ion_roundtrip(payload : @ion.IonValue) -> Outcome {
  try @partiql_ion.from_ion(payload) catch {
    error => Fail(@debug.to_string(error))
  } noraise {
    Ion(_) as v =>
      if @partiql_ion.to_ion(v).equals(payload) {
        Pass
      } else {
        Fail("$ion payload changed in the round trip")
      }
    other => Fail("decoded to \{@debug.to_string(other)}, not an Ion value")
  }
}

///|
test "print-roundtrip check" {
  @expect.expect_all(soft => {
    soft
    .expect(check_print_roundtrip("select a from t where x = 1"))
    .to_equal(Pass)
    soft.expect(check_print_roundtrip("(g MATCH (a)->(b))")).to_equal(Pass)
    soft.expect(check_print_roundtrip("SELECT FROM")).to_equal(NotApplicable)
  })
}

///|
/// The M3 exit criterion: printing a parsed statement and parsing the text
/// gives the same tree (spans aside), and printing is a fixpoint. Statements
/// that do not parse are not applicable.
fn check_print_roundtrip(statement : String) -> Outcome {
  let first = @syntax.parse(statement) catch { _ => return NotApplicable }
  let printed = @syntax.print(first)
  let second = @syntax.parse(printed) catch {
    e =>
      return Fail(
        "printed text does not parse: \{printed}: \{@debug.to_string(e)}",
      )
  }
  if second.strip_spans() != first.strip_spans() {
    return Fail("a different tree after printing: \{printed}")
  }
  if @syntax.print(second) != printed {
    return Fail("printing is not a fixpoint: \{printed}")
  }
  Pass
}
