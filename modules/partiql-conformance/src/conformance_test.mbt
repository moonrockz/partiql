///|
/// Results of one check over the whole corpus.
priv struct Tally {
  check : String
  passed : Array[String]
  failed : Map[String, String]
  mut not_applicable : Int
  /// How many outcomes were recorded. Each id is recorded once.
  mut records : Int
}

///|
fn Tally::new(check : String) -> Tally {
  { check, passed: [], failed: {}, not_applicable: 0, records: 0, }
}

///|
fn Tally::record(self : Tally, id : String, outcome : Outcome) -> Unit {
  self.records += 1
  match outcome {
    Pass => self.passed.push(id)
    Fail(reason) => self.failed[id] = reason
    NotApplicable => self.not_applicable += 1
  }
}

///|
/// Records the codec check for one corpus value, and the ion-roundtrip check
/// for each `$ion` payload inside it.
fn record_value(
  id : String,
  value : @ion.IonValue,
  codec : Tally,
  ion_roundtrip : Tally,
) -> Unit {
  codec.record(id, check_codec(value))
  for k, payload in ion_payloads(value) {
    ion_roundtrip.record("\{id}#ion[\{k}]", check_ion_roundtrip(payload))
  }
}

///|
fn run_case(
  suite : Suite,
  case : TestCase,
  syntax : Tally,
  eval_parse : Tally,
  codec : Tally,
  ion_roundtrip : Tally,
  print_roundtrip : Tally,
  pretty_roundtrip : Tally,
  recovery : Tally,
  eval : Tally,
) -> Unit {
  let statements = suite.statements_of(case) catch {
    error => {
      syntax.record(case.id, Fail(@debug.to_string(error)))
      return
    }
  }
  let expects_success = case.assertions.iter().any(a => a is SyntaxSuccess)
  let expects_failure = case.assertions.iter().any(a => a is SyntaxFail)
  let static_analysis = case.assertions.iter().any(a => a is StaticAnalysisFail)
  let evaluates = case.assertions
    .iter()
    .any(a => a is (EvaluationSuccess(_) | EvaluationFail(_)))
  let many = statements.length() > 1
  // Each check records an id at most once, even when a case has several
  // assertions (for example one per evaluation mode).
  for i, statement in statements {
    let id = if many { "\{case.id}[\{i}]" } else { case.id }
    if expects_success {
      syntax.record(id, check_syntax(true, statement))
    } else if expects_failure {
      syntax.record(id, check_syntax(false, statement))
    } else if static_analysis {
      syntax.record(id, NotApplicable)
    }
    if evaluates {
      eval_parse.record(id, check_parses(statement))
    }
    if expects_success || evaluates {
      print_roundtrip.record(id, check_print_roundtrip(statement))
      pretty_roundtrip.record(id, check_pretty_roundtrip(statement))
    }
    if expects_success || expects_failure || evaluates {
      recovery.record(id, check_recovery(statement))
    }
  }
  if case.env is Some(env) {
    record_value("\{case.id}#env", env, codec, ion_roundtrip)
  }
  for i, assertion in case.assertions {
    if assertion is EvaluationSuccess(output~, ..) {
      record_value("\{case.id}#output[\{i}]", output, codec, ion_roundtrip)
    }
  }
  record_eval(case, statements, eval)
}

///|
/// Evaluates each statement under each mode of each evaluation assertion.
/// Equivalence-class statements are not applicable in M4a.
fn record_eval(
  case : TestCase,
  statements : Array[String],
  eval : Tally,
) -> Unit {
  let many = statements.length() > 1
  for i, statement in statements {
    let id = if many { "\{case.id}[\{i}]" } else { case.id }
    for assertion in case.assertions {
      let (modes, expected) = match assertion {
        EvaluationSuccess(output~, modes~) => (modes, Some(Value(output)))
        EvaluationFail(modes~) => (modes, Some(Failure))
        _ => ([], None)
      }
      for mode in modes {
        let name = match mode {
          Coerce => "coerce"
          Error => "error"
        }
        let outcome = match (case.statement, expected) {
          (Text(_), Some(expected)) =>
            check_eval(statement, case.env, mode, expected)
          _ => NotApplicable
        }
        eval.record("\{id}#\{name}", outcome)
      }
    }
  }
}

///|
/// Decodes one file. A file that does not decode is recorded once as a
/// failure, so it is visible and counts against the suite.
fn read_suite(path : String, file_id : String, syntax : Tally) -> Suite? {
  let text = @fs.read_file_to_string(path) catch {
    error => {
      syntax.record("\{file_id}::<file>", Fail(@debug.to_string(error)))
      return None
    }
  }
  let values = @text.read_ion_datagram(text) catch {
    error => {
      syntax.record("\{file_id}::<file>", Fail(@debug.to_string(error)))
      return None
    }
  }
  let suite = decode_suite(file_id, values) catch {
    error => {
      syntax.record("\{file_id}::<file>", Fail(@debug.to_string(error)))
      return None
    }
  }
  Some(suite)
}

///|
test "partiql-tests" {
  require_data_root(data_roots[0])
  let syntax = Tally::new("syntax")
  let eval_parse = Tally::new("eval-parse")
  let codec = Tally::new("codec")
  let ion_roundtrip = Tally::new("ion-roundtrip")
  let print_roundtrip = Tally::new("print-roundtrip")
  let pretty_roundtrip = Tally::new("pretty-roundtrip")
  let recovery = Tally::new("recovery")
  let eval = Tally::new("eval")
  for root in data_roots {
    if !@fs.path_exists(root) {
      continue
    }
    for path in ion_files_under(root) {
      let relative = path.view(start_offset=root.length() + 1).to_owned()
      let file_id = if root.has_suffix("-extended") {
        "extended/" + relative
      } else {
        relative
      }
      guard read_suite(path, file_id, syntax) is Some(suite) else { continue }
      for case in suite.cases {
        run_case(
          suite, case, syntax, eval_parse, codec, ion_roundtrip, print_roundtrip,
          pretty_roundtrip, recovery, eval,
        )
      }
    }
  }
  let ratchet = @env.get_env_var("PARTIQL_CONFORMANCE_MODE") == Some("ratchet")
  let allow_drop = @env.get_env_var("PARTIQL_CONFORMANCE_ALLOW_DROP") ==
    Some("1")
  let mut regressions = 0
  for
    tally in [
      syntax, eval_parse, codec, ion_roundtrip, print_roundtrip, pretty_roundtrip,
      recovery, eval,
    ] {
    let comparison = compare(load_baseline(tally.check), tally.passed)
    report_conformance(
      suite=tally.check,
      total=tally.passed.length() + tally.failed.length() + tally.not_applicable,
      passed=tally.passed.length(),
      not_applicable=tally.not_applicable,
      comparison~,
    )
    let (save, failing) = ratchet_outcome(
      comparison.regressions.length(),
      ratchet,
      allow_drop,
    )
    if save {
      save_baseline(tally.check, tally.passed)
    }
    regressions += failing
  }
  if regressions > 0 {
    fail(
      "\{regressions} conformance regressions; see the CONFORMANCE lines above. To drop ids on purpose (pin bump), run the ratchet with PARTIQL_CONFORMANCE_ALLOW_DROP=1",
    )
  }
}

///|
test "a case with several evaluation assertions is checked once per statement" {
  let suite = decode_suite(
    "f.ion",
    @text.read_ion_datagram(
      (
        #|{ name: "n", statement: "1",
        #|  assert: [ { result: EvaluationSuccess, evalMode: EvalModeCoerce, output: 1 },
        #|            { result: EvaluationFail, evalMode: EvalModeError } ] }
      ),
    ),
  )
  let syntax = Tally::new("syntax")
  let eval_parse = Tally::new("eval-parse")
  let codec = Tally::new("codec")
  let ion_roundtrip = Tally::new("ion-roundtrip")
  let print_roundtrip = Tally::new("print-roundtrip")
  let pretty_roundtrip = Tally::new("pretty-roundtrip")
  let recovery = Tally::new("recovery")
  let eval = Tally::new("eval")
  run_case(
    suite,
    suite.cases[0],
    syntax,
    eval_parse,
    codec,
    ion_roundtrip,
    print_roundtrip,
    pretty_roundtrip,
    recovery,
    eval,
  )
  @expect.expect(eval_parse.records).to_equal(1)
  @expect.expect(syntax.records).to_equal(0)
}

///|
/// Whether to save the baseline, and how many regressions fail the test. A
/// ratchet never drops baseline ids unless `allow_drop` is set (for example
/// after a pin bump removes tests).
fn ratchet_outcome(
  regressions : Int,
  ratchet : Bool,
  allow_drop : Bool,
) -> (Bool, Int) {
  if ratchet && (regressions == 0 || allow_drop) {
    (true, 0)
  } else {
    (false, regressions)
  }
}

///|
test "ratchet keeps baseline ids unless dropping is allowed" {
  // Check mode: never save; regressions fail.
  @expect.expect(ratchet_outcome(2, false, false)).to_equal((false, 2))
  // Ratchet mode without regressions: save.
  @expect.expect(ratchet_outcome(0, true, false)).to_equal((true, 0))
  // Ratchet mode with regressions: refuse to drop ids, fail.
  @expect.expect(ratchet_outcome(2, true, false)).to_equal((false, 2))
  // Ratchet mode with regressions and explicit permission (pin bump): save.
  @expect.expect(ratchet_outcome(2, true, true)).to_equal((true, 0))
}
