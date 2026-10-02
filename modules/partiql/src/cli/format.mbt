// `partiql format` (spec M3a section 9; rendered errors from M3c).

///|
fn format_command(m : @argparse.Matches, io : Io, color : Bool) -> Outcome {
  let out = StringBuilder()
  let errors = StringBuilder()
  let inputs = match read_inputs("format", m, io, errors) {
    Ok(inputs) => inputs
    Err(outcome) => return outcome
  }
  let write = m.flags.get("write") == Some(true)
  let many = m.values.get("file").unwrap_or([]).length() > 1
  for input in inputs {
    try @syntax.format(input.source) catch {
      e =>
        errors.write_string(
          @syntax.render(e, input.source, name=input.name, color~),
        )
    } noraise {
      text =>
        if write {
          (io.write_file)(input.name, text) catch {
            e =>
              errors.write_string(
                "partiql format: \{input.name}: \{error_text(e)}\n",
              )
          }
        } else {
          if many {
            out.write_string("-- \{input.name}\n")
          }
          out.write_string(text)
        }
    }
  }
  finish(out, errors)
}
