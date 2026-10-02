// `partiql format` (spec M3a section 9).

///|
/// The message of an I/O error: the text of a `Failure`, else the error.
fn error_text(e : Error) -> String {
  match e {
    Failure(message) => message
    _ => e.to_string()
  }
}

///|
fn position_message(
  label : String,
  source : String,
  e : @syntax.ParseError,
) -> String {
  let (message, span) = match e {
    Syntax(message~, span~, ..) => (message, span)
    Unsupported(message~, span~) => (message, span)
  }
  let ((line, column), _) = span.line_column(source)
  "\{label}:\{line}:\{column}: \{message}\n"
}

///|
/// The formatted text of `source`, or an error line labelled `label`.
fn format_source(label : String, source : String) -> Result[String, String] {
  try @syntax.format(source) catch {
    e => Err(position_message(label, source, e))
  } noraise {
    text => Ok(text)
  }
}

///|
fn format_command(m : @argparse.Matches, io : Io) -> Outcome {
  let write = m.flags.get("write") == Some(true)
  let files = m.values.get("file").unwrap_or([])
  let usage = (text : String) => {
    usage_error(
      "partiql format: \{text}\nRun 'partiql help format' for more information.\n",
    )
  }
  if m.values.get("expr") is Some([statement, ..]) {
    if write || !files.is_empty() {
      return usage("-e takes no files and no --write")
    }
    return match format_source("<expr>", statement) {
      Ok(text) => success(text)
      Err(line) => { stdout: "", stderr: line, status: 1, }
    }
  }
  if files.is_empty() || files == ["-"] {
    if write {
      return usage("--write needs at least one file")
    }
    let source = (io.read_stdin)() catch {
      e =>
        return {
          stdout: "",
          stderr: "partiql format: <stdin>: \{error_text(e)}\n",
          status: 1,
        }
    }
    return match format_source("<stdin>", source) {
      Ok(text) => success(text)
      Err(line) => { stdout: "", stderr: line, status: 1, }
    }
  }
  if files.contains("-") {
    return usage("'-' (stdin) cannot be mixed with files")
  }
  let out = StringBuilder()
  let err = StringBuilder()
  for path in files {
    let source = (io.read_file)(path) catch {
      e => {
        err.write_string("partiql format: \{path}: \{error_text(e)}\n")
        continue
      }
    }
    match format_source(path, source) {
      Err(line) => err.write_string(line)
      Ok(text) =>
        if write {
          (io.write_file)(path, text) catch {
            e => err.write_string("partiql format: \{path}: \{error_text(e)}\n")
          }
        } else {
          if files.length() > 1 {
            out.write_string("-- \{path}\n")
          }
          out.write_string(text)
        }
    }
  }
  let errors = err.to_string()
  {
    stdout: out.to_string(),
    stderr: errors,
    status: if errors == "" {
      0
    } else {
      1
    },
  }
}

///|
/// Whether `args` make `run` read stdin, so that `main` reads it first.
pub fn reads_stdin(args : ArrayView[String]) -> Bool {
  let matches = command_line().parse(argv=args, env={}) catch {
    _ => return false
  }
  match matches.subcommand {
    Some(("format", m)) => {
      let files = m.values.get("file").unwrap_or([])
      m.values.get("expr") is None && (files.is_empty() || files == ["-"])
    }
    _ => false
  }
}
