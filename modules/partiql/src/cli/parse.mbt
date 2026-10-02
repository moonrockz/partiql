// `partiql parse` and `partiql check` (spec M3c §6).

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
    try @syntax.parse_script(input.source) catch {
      e =>
        errors.write_string(
          @syntax.render(e, input.source, name=input.name, color~),
        )
    } noraise {
      script => {
        if many {
          out.write_string(";; \{input.name}\n")
        }
        for s in script.statements {
          out.write_string(@syntax.to_sexp(s) + "\n")
        }
      }
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
    ignore(@syntax.parse_script(input.source)) catch {
      e =>
        errors.write_string(
          @syntax.render(e, input.source, name=input.name, color~),
        )
    }
  }
  finish(StringBuilder(), errors)
}
