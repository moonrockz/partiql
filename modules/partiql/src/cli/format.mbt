// `partiql format` (spec M3a section 9; rendered errors from M3c; layout
// width from M3b).

///|
fn format_command(m : @argparse.Matches, io : Io, color : Bool) -> Outcome {
  let width = match format_width(m) {
    Ok(width) => width
    Err(text) =>
      return usage_error(
        "partiql format: \{text}\nRun 'partiql help format' for more information.\n",
      )
  }
  let out = StringBuilder()
  let errors = StringBuilder()
  let inputs = match read_inputs("format", m, io, errors) {
    Ok(inputs) => inputs
    Err(outcome) => return outcome
  }
  let write = m.flags.get("write") == Some(true)
  let many = m.values.get("file").unwrap_or([]).length() > 1
  for input in inputs {
    let r = @syntax.parse_script_recovering(input.source)
    if !r.errors.is_empty() {
      // Every error; nothing is printed or written for a broken input.
      for e in r.errors {
        errors.write_string(
          @syntax.render(e, input.source, name=input.name, color~),
        )
      }
      continue
    }
    // Valid input: the recovered script is the strict script.
    let text = @syntax.print_script(r.script, width?)
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
  finish(out, errors)
}

///|
/// The layout width: 80 by default, `--width N`, or none (the canonical
/// one-line form) for `--compact`.
fn format_width(m : @argparse.Matches) -> Result[Int?, String] {
  let compact = m.flags.get("compact") == Some(true)
  match m.values.get("width") {
    Some([text, ..]) => {
      if compact {
        return Err("--compact takes no --width")
      }
      let n = @string.parse_int(text) catch {
        _ => return Err("--width must be a whole number of at least 1")
      }
      if n < 1 {
        return Err("--width must be a whole number of at least 1")
      }
      Ok(Some(n))
    }
    _ => Ok(if compact { None } else { Some(80) })
  }
}
