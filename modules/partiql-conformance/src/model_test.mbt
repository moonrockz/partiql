///|
fn decode_text(text : String) -> Suite raise {
  decode_suite("f.ion", @text.read_ion_datagram(text))
}

///|
test "a nsd syntax test" {
  let suite = decode_text(
    (
      #|'literal'::[ { name: "missing", statement: "missing", assert: [ { result: SyntaxSuccess } ] } ]
    ),
  )
  @expect.expect(suite.cases.length()).to_equal(1)
  let case = suite.cases[0]
  @expect.expect(case.id).to_equal("f.ion::literal::missing")
  @expect.expect(case.statement).to_equal(Statements::Text("missing"))
  match case.assertions {
    [SyntaxSuccess] => ()
    other => fail("unexpected assertions \{@debug.to_string(other)}")
  }
}

///|
test "a single assert struct and a syntax failure" {
  let suite = decode_text(
    (
      #|{ name: "too many dots", statement: "x...a", assert: { result: SyntaxFail } }
    ),
  )
  @expect.expect(suite.cases[0].id).to_equal("f.ion::too many dots")
  match suite.cases[0].assertions {
    [SyntaxFail] => ()
    other => fail("unexpected assertions \{@debug.to_string(other)}")
  }
}

///|
test "envs apply to the cases after them in the same ns" {
  let suite = decode_text(
    (
      #|'select-star'::[
      #|  { name: "before", statement: "1", assert: { result: SyntaxSuccess } },
      #|  envs::{ t: [1] },
      #|  { name: "after", statement: "SELECT * FROM t",
      #|    assert: { result: EvaluationSuccess, evalMode: [EvalModeCoerce, EvalModeError],
      #|              output: $bag::[1] } } ]
    ),
  )
  @expect.expect(suite.cases[0].env is None).to_be_true()
  @expect.expect(suite.cases[1].env is Some(_)).to_be_true()
  match suite.cases[1].assertions {
    [EvaluationSuccess(modes~, ..)] =>
      @expect.expect(modes).to_equal([EvalMode::Coerce, EvalMode::Error])
    other => fail("unexpected assertions \{@debug.to_string(other)}")
  }
}

///|
test "a case env overrides the ns env" {
  let suite = decode_text(
    (
      #|envs::{ a: 1 }
      #|{ name: "n", statement: "a", env: { a: 2 }, assert: { result: EvaluationFail, evalMode: EvalModeError } }
    ),
  )
  let env = suite.cases[0].env.unwrap()
  @expect.expect(env.equals(@text.read_ion("{ a: 2 }"))).to_be_true()
}

///|
test "equiv_class statements" {
  let suite = decode_text(
    (
      #|equiv_class::{ id: one, statements: ["1", "(1)"] }
      #|{ name: "n", statement: one, assert: { result: EvaluationSuccess, evalMode: EvalModeCoerce, output: 1 } }
    ),
  )
  let case = suite.cases[0]
  @expect.expect(case.statement).to_equal(Statements::EquivClass("one"))
  @expect.expect(suite.statements_of(case)).to_equal(["1", "(1)"])
}

///|
test "unknown equiv_class" {
  let suite = decode_text(
    (
      #|{ name: "n", statement: nope, assert: { result: SyntaxSuccess } }
    ),
  )
  try suite.statements_of(suite.cases[0]) catch {
    error =>
      @expect.expect(@debug.to_string(error)).to_contain(
        "unknown equiv_class nope",
      )
  } noraise {
    statements =>
      fail("expected an error, got \{statements.length()} statements")
  }
}

///|
test "duplicate names get a suffix" {
  let suite = decode_text(
    (
      #|{ name: "same", statement: "1", assert: { result: SyntaxSuccess } }
      #|{ name: "same", statement: "2", assert: { result: SyntaxSuccess } }
    ),
  )
  @expect.expect(suite.cases.map(c => c.id)).to_equal([
    "f.ion::same", "f.ion::same#2",
  ])
}

///|
test "a case without assert is malformed" {
  let text =
    #|{ name: "n", statement: "1" }
  try decode_text(text) catch {
    error =>
      @expect.expect(@debug.to_string(error)).to_contain("without assert")
  } noraise {
    _ => fail("expected a malformed-suite error")
  }
}

///|
enum EvalMode {
  Coerce
  Error
} derive(Debug, Eq)

///|
enum Assertion {
  SyntaxSuccess
  SyntaxFail
  StaticAnalysisFail
  EvaluationSuccess(output~ : @ion.IonValue, modes~ : Array[EvalMode])
  EvaluationFail(modes~ : Array[EvalMode])
} derive(Debug)

///|
/// The statement of a test case: its text, or the id of an `equiv_class`
/// whose statements are all equivalent.
enum Statements {
  Text(String)
  EquivClass(String)
} derive(Debug, Eq)

///|
struct TestCase {
  /// `<file>::<ns>::...::<name>`, unique in the suite.
  id : String
  statement : Statements
  env : @ion.IonValue?
  assertions : Array[Assertion]
} derive(Debug)

///|
struct Suite {
  cases : Array[TestCase]
  equiv_classes : Map[String, Array[String]]
} derive(Debug)

///|
suberror SuiteError {
  Malformed(String)
} derive(Debug)

///|
fn annotation_texts(value : @ion.IonValue) -> Array[String] {
  value.annotations().filter_map(token => token.text())
}

///|
fn text_of(value : @ion.IonValue) -> String? {
  match value.kind() {
    String(s) => Some(s)
    Symbol(token) => token.text()
    _ => None
  }
}

///|
fn field(fields : Array[@ion.Field], name : String) -> @ion.IonValue? {
  for f in fields {
    if f.name().text() == Some(name) {
      return Some(f.value())
    }
  }
  None
}

///|
fn decode_modes(value : @ion.IonValue?) -> Array[EvalMode] raise SuiteError {
  let items = match value {
    None => []
    Some(v) =>
      match v.kind() {
        List(items) => items
        _ => [v]
      }
  }
  items.map(item => {
    match text_of(item) {
      Some("EvalModeCoerce") => EvalMode::Coerce
      Some("EvalModeError") => EvalMode::Error
      _ =>
        raise SuiteError::Malformed(
          "unknown evalMode \{@debug.to_string(item)}",
        )
    }
  })
}

///|
fn decode_assertion(value : @ion.IonValue) -> Assertion raise SuiteError {
  guard value.kind() is Struct(fields) else {
    raise SuiteError::Malformed("assert is not a struct")
  }
  let modes = decode_modes(field(fields, "evalMode"))
  match field(fields, "result").bind(text_of) {
    Some("SyntaxSuccess") => SyntaxSuccess
    Some("SyntaxFail") => SyntaxFail
    Some("StaticAnalysisFail") => StaticAnalysisFail
    Some("EvaluationSuccess") =>
      match field(fields, "output") {
        Some(output) => EvaluationSuccess(output~, modes~)
        None => raise SuiteError::Malformed("EvaluationSuccess without output")
      }
    Some("EvaluationFail") => EvaluationFail(modes~)
    other =>
      raise SuiteError::Malformed("unknown result \{@debug.to_string(other)}")
  }
}

///|
/// Decoder state for one file: the ns path, the active environment,
/// and the ids seen so far.
priv struct Decoder {
  file : String
  cases : Array[TestCase]
  equiv_classes : Map[String, Array[String]]
  seen : Map[String, Int]
}

///|
fn Decoder::unique_id(self : Decoder, base : String) -> String {
  let count = self.seen.get(base).unwrap_or(0) + 1
  self.seen[base] = count
  if count == 1 {
    base
  } else {
    "\{base}#\{count}"
  }
}

///|
fn Decoder::decode_case(
  self : Decoder,
  path : Array[String],
  env : @ion.IonValue?,
  fields : Array[@ion.Field],
) -> Unit raise SuiteError {
  guard field(fields, "name").bind(text_of) is Some(name) else {
    raise SuiteError::Malformed("test case without name in \{self.file}")
  }
  let statement = match field(fields, "statement") {
    Some(v) =>
      match v.kind() {
        String(s) => Statements::Text(s)
        Symbol(token) =>
          match token.text() {
            Some(id) => Statements::EquivClass(id)
            None =>
              raise SuiteError::Malformed(
                "statement symbol without text: \{name}",
              )
          }
        _ =>
          raise SuiteError::Malformed(
            "statement is not a string or symbol: \{name}",
          )
      }
    None => raise SuiteError::Malformed("test case without statement: \{name}")
  }
  let assertions = match field(fields, "assert") {
    Some(v) =>
      match v.kind() {
        List(items) => items.map(decode_assertion)
        _ => [decode_assertion(v)]
      }
    None => raise SuiteError::Malformed("test case without assert: \{name}")
  }
  let case_env = match field(fields, "env") {
    Some(e) => Some(e)
    None => env
  }
  let base = [self.file, ..path, name].join("::")
  self.cases.push({
    id: self.unique_id(base),
    statement,
    env: case_env,
    assertions,
  })
}

///|
fn Decoder::decode_values(
  self : Decoder,
  path : Array[String],
  inherited_env : @ion.IonValue?,
  values : Array[@ion.IonValue],
) -> Unit raise SuiteError {
  let mut env = inherited_env
  for value in values {
    let annotations = annotation_texts(value)
    match (value.kind(), annotations) {
      (Struct(_), ["envs", ..]) => env = Some(value.with_annotations([]))
      (Struct(fields), ["equiv_class", ..]) => {
        guard field(fields, "id").bind(text_of) is Some(id) else {
          raise SuiteError::Malformed("equiv_class without id")
        }
        guard field(fields, "statements") is Some(statements) &&
          statements.kind() is List(items) else {
          raise SuiteError::Malformed("equiv_class \{id} without statements")
        }
        self.equiv_classes[id] = items.filter_map(text_of)
      }
      (Struct(fields), _) => self.decode_case(path, env, fields)
      (List(items), [ns, ..]) => self.decode_values([..path, ns], env, items)
      (List(items), []) => self.decode_values(path, env, items)
      _ =>
        raise SuiteError::Malformed(
          "unexpected top-level value in \{self.file}",
        )
    }
  }
}

///|
/// Decodes one partiql-tests file. `file` is its path under the data root;
/// it becomes the first part of every test id.
fn decode_suite(
  file : String,
  values : Array[@ion.IonValue],
) -> Suite raise SuiteError {
  let decoder : Decoder = { file, cases: [], equiv_classes: {}, seen: {}, }
  decoder.decode_values([], None, values)
  { cases: decoder.cases, equiv_classes: decoder.equiv_classes, }
}

///|
/// The statement texts to check for `case`: one, or all statements of its
/// equivalence class.
fn Suite::statements_of(
  self : Suite,
  case : TestCase,
) -> Array[String] raise SuiteError {
  match case.statement {
    Text(text) => [text]
    EquivClass(id) =>
      match self.equiv_classes.get(id) {
        Some(statements) => statements
        None =>
          raise SuiteError::Malformed("unknown equiv_class \{id} in \{case.id}")
      }
  }
}
