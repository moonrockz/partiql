///|
test "syntax check treats Unsupported as failure" {
  // The M0 parser raises Unsupported for everything. Neither SyntaxSuccess
  // nor SyntaxFail may count that as a pass.
  @expect.expect(check_syntax(true, "1") is Fail(_)).to_be_true()
  @expect.expect(check_syntax(false, "x...a") is Fail(_)).to_be_true()
}

///|
test "codec check passes for MISSING and fails for an unsupported value" {
  @expect.expect(check_codec(@text.read_ion("$missing::null"))).to_equal(Pass)
  @expect.expect(check_codec(@text.read_ion("1")) is Fail(_)).to_be_true()
}

///|
enum Outcome {
  Pass
  Fail(String)
  NotApplicable
} derive(Debug, Eq)

///|
/// `expect_success` is true for SyntaxSuccess and false for SyntaxFail.
fn check_syntax(expect_success : Bool, statement : String) -> Outcome {
  try @syntax.parse(statement) catch {
    Unsupported(reason) => Fail("unsupported: \{reason}")
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
/// Decodes `value` as PartiQL-encoded Ion and encodes it back.
fn check_codec(value : @ion.IonValue) -> Outcome {
  try @partiql_ion.from_ion(value) catch {
    Unsupported(reason) => Fail("unsupported: \{reason}")
    Malformed(reason) => Fail("malformed: \{reason}")
  } noraise {
    decoded =>
      if @partiql_ion.to_ion(decoded).equals(value) {
        Pass
      } else {
        Fail("round trip changed the value")
      }
  }
}
