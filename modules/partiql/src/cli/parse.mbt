// `partiql parse` and `partiql check` (spec M3c §6; every error from M3d).

///|
fn parse_command(m : @argparse.Matches, io : Io, color : Bool) -> Outcome {
  let out = StringBuilder()
  let errors = StringBuilder()
  let inputs = match read_inputs("parse", m, io, errors) {
    Ok(inputs) => inputs
    Err(outcome) => return outcome
  }
  let many = m.values.get("file").unwrap_or([]).length() > 1
  for input in inputs {
    let r = @syntax.parse_script_recovering(input.source)
    for e in r.errors {
      errors.write_string(
        @syntax.render(e, input.source, name=input.name, color~),
      )
    }
    if many {
      out.write_string(";; \{input.name}\n")
    }
    // A broken input prints its partial tree; broken parts are (error).
    for s in r.script.statements {
      out.write_string(@syntax.to_sexp(s) + "\n")
    }
  }
  finish(out, errors)
}

///|
fn check_command(m : @argparse.Matches, io : Io, color : Bool) -> Outcome {
  let errors = StringBuilder()
  let inputs = match read_inputs("check", m, io, errors) {
    Ok(inputs) => inputs
    Err(outcome) => return outcome
  }
  for input in inputs {
    for e in @syntax.parse_script_recovering(input.source).errors {
      errors.write_string(
        @syntax.render(e, input.source, name=input.name, color~),
      )
    }
  }
  finish(StringBuilder(), errors)
}
