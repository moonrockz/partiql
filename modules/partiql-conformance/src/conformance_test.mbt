///|
/// Results of one check over the whole corpus.
priv struct Tally {
  check : String
  passed : Array[String]
  failed : Map[String, String]
  mut not_applicable : Int
}

///|
fn Tally::new(check : String) -> Tally {
  { check, passed: [], failed: {}, not_applicable: 0, }
}

///|
fn Tally::record(self : Tally, id : String, outcome : Outcome) -> Unit {
  match outcome {
    Pass => self.passed.push(id)
    Fail(reason) => self.failed[id] = reason
    NotApplicable => self.not_applicable += 1
  }
}

///|
fn run_case(
  suite : Suite,
  case : TestCase,
  syntax : Tally,
  eval_parse : Tally,
  codec : Tally,
) -> Unit {
  let statements = suite.statements_of(case) catch {
    error => {
      syntax.record(case.id, Fail(@debug.to_string(error)))
      return
    }
  }
  let many = statements.length() > 1
  for i, statement in statements {
    let id = if many { "\{case.id}[\{i}]" } else { case.id }
    for assertion in case.assertions {
      match assertion {
        SyntaxSuccess => syntax.record(id, check_syntax(true, statement))
        SyntaxFail => syntax.record(id, check_syntax(false, statement))
        StaticAnalysisFail => syntax.record(id, NotApplicable)
        EvaluationSuccess(_) | EvaluationFail(_) =>
          eval_parse.record(id, check_parses(statement))
      }
    }
  }
  if case.env is Some(env) {
    codec.record("\{case.id}#env", check_codec(env))
  }
  for i, assertion in case.assertions {
    if assertion is EvaluationSuccess(output~, ..) {
      codec.record("\{case.id}#output[\{i}]", check_codec(output))
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
        run_case(suite, case, syntax, eval_parse, codec)
      }
    }
  }
  let ratchet = @env.get_env_var("PARTIQL_CONFORMANCE_MODE") == Some("ratchet")
  let mut regressions = 0
  for tally in [syntax, eval_parse, codec] {
    if ratchet {
      save_baseline(tally.check, tally.passed)
    }
    let comparison = compare(load_baseline(tally.check), tally.passed)
    report_conformance(
      suite=tally.check,
      total=tally.passed.length() + tally.failed.length() + tally.not_applicable,
      passed=tally.passed.length(),
      not_applicable=tally.not_applicable,
      comparison~,
    )
    regressions += comparison.regressions.length()
  }
  if regressions > 0 {
    fail(
      "\{regressions} conformance regressions; see the CONFORMANCE lines above",
    )
  }
}
