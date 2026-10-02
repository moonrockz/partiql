// Input handling shared by `parse`, `check` and `format` (spec M3c §6).

///|
priv struct Input {
  name : String
  source : String
}

///|
/// The message of an I/O error: the text of a `Failure`, else the error.
fn error_text(e : Error) -> String {
  match e {
    Failure(message) => message
    _ => e.to_string()
  }
}

///|
/// Whether a command reads stdin: no `-e`, no `--write`, and no file or only
/// `-`. `read_inputs` and `reads_stdin` share this rule.
fn stdin_wanted(m : @argparse.Matches) -> Bool {
  let files = m.values.get("file").unwrap_or([])
  m.values.get("expr") is None &&
  m.flags.get("write") != Some(true) &&
  (files.is_empty() || files == ["-"])
}

///|
/// The inputs of `command`: `-e`, files or stdin. Unreadable inputs are
/// reported in `errors`; misuse is a usage error.
fn read_inputs(
  command : String,
  m : @argparse.Matches,
  io : Io,
  errors : StringBuilder,
) -> Result[Array[Input], Outcome] {
  let write = m.flags.get("write") == Some(true)
  let files = m.values.get("file").unwrap_or([])
  let usage = (text : String) => {
    usage_error(
      "partiql \{command}: \{text}\nRun 'partiql help \{command}' for more information.\n",
    )
  }
  if m.values.get("expr") is Some([statement, ..]) {
    if write || !files.is_empty() {
      return Err(usage("-e takes no files and no --write"))
    }
    return Ok([{ name: "<expr>", source: statement, }])
  }
  if write && (files.is_empty() || files == ["-"]) {
    return Err(usage("--write needs at least one file"))
  }
  if stdin_wanted(m) {
    let source = (io.read_stdin)() catch {
      e => {
        errors.write_string("partiql \{command}: <stdin>: \{error_text(e)}\n")
        return Ok([])
      }
    }
    return Ok([{ name: "<stdin>", source, }])
  }
  if files.contains("-") {
    return Err(usage("'-' (stdin) cannot be mixed with files"))
  }
  let inputs : Array[Input] = []
  for path in files {
    let source = (io.read_file)(path) catch {
      e => {
        errors.write_string("partiql \{command}: \{path}: \{error_text(e)}\n")
        continue
      }
    }
    inputs.push({ name: path, source, })
  }
  Ok(inputs)
}

///|
fn finish(out : StringBuilder, errors : StringBuilder) -> Outcome {
  let stderr = errors.to_string()
  { stdout: out.to_string(), stderr, status: if stderr == "" { 0 } else { 1 }, }
}

///|
/// Whether `args` make `run` read stdin, so that `main` reads it first.
pub fn reads_stdin(args : ArrayView[String]) -> Bool {
  // `run` answers help before it parses (see `help_request`).
  if help_request(args) is Some(_) {
    return false
  }
  let matches = command_line().parse(argv=args, env={}) catch {
    _ => return false
  }
  match matches.subcommand {
    Some(("format" | "parse" | "check", m)) => stdin_wanted(m)
    _ => false
  }
}
