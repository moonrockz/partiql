// `partiql query` (spec M4e): evaluates statements against global bindings
// read from Ion, and prints each result as PartiQL-encoded Ion.

///|
fn query_command(m : @argparse.Matches, io : Io, color : Bool) -> Outcome {
  let usage = (text : String) => {
    usage_error(
      "partiql query: \{text}\nRun 'partiql help query' for more information.\n",
    )
  }
  let datas = match data_args(m) {
    Ok(datas) => datas
    Err(text) => return usage(text)
  }
  if query_stdin_readers(m) > 1 {
    return usage("only one input can read stdin")
  }
  let out = StringBuilder()
  let errors = StringBuilder()
  let inputs = match read_inputs("query", m, io, errors) {
    Ok(inputs) => inputs
    Err(outcome) => return outcome
  }
  let globals = load_bindings(
    m.values.get("env").unwrap_or([]),
    datas,
    io,
    errors,
  )
  if errors.to_string() != "" {
    return finish(out, errors)
  }
  // Every input must parse before any statement runs.
  let scripts : Array[(Input, Array[@syntax.Statement])] = []
  for input in inputs {
    let r = @syntax.parse_script_recovering(input.source)
    for e in r.errors {
      errors.write_string(
        @syntax.render(e, input.source, name=input.name, color~),
      )
    }
    scripts.push((input, r.script.statements))
  }
  if errors.to_string() != "" {
    return finish(out, errors)
  }
  let env = @eval.Bindings::of_pairs(globals)
  let mode : @eval.Mode = if m.flags.get("strict") == Some(true) {
    Strict
  } else {
    Permissive
  }
  let compact = m.flags.get("compact") == Some(true)
  for script in scripts {
    let (input, statements) = script
    for statement in statements {
      let value = @eval.evaluate(statement, env~, mode~, clock=io.clock) catch {
        e => {
          errors.write_string(eval_error_text(e, input, color))
          return finish(out, errors)
        }
      }
      let ion = @partiql_ion.to_ion(value)
      let text = try {
        if compact {
          @text.write_ion(ion)
        } else {
          @text.write_ion_pretty(ion)
        }
      } catch {
        e => {
          errors.write_string(
            "partiql query: \{input.name}: cannot write the result: \{e.message()}\n",
          )
          return finish(out, errors)
        }
      }
      out.write_string(text + "\n")
    }
  }
  finish(out, errors)
}

///|
/// The rendered diagnostic of an evaluation error in `input` (spec M4e §6).
fn eval_error_text(e : @eval.EvalError, input : Input, color : Bool) -> String {
  let (message, span) = match e {
    TypeError(message~, span~) => ("type error: " + message, span)
    DataError(message~, span~) => ("data error: " + message, span)
    // The message already says "is not supported yet" (plan ruling 2).
    Unsupported(message~, span~) => (message, span)
    Syntax(p) => return @syntax.render(p, input.source, name=input.name, color~)
  }
  @syntax.render_message(message, span, input.source, name=input.name, color~)
}

///|
/// A `--data NAME=FILE` argument.
priv struct DataArg {
  name : String
  file : String
}

///|
/// `NAME=FILE`, split at the first `=`. `None` when there is no `=` or the
/// name or the file is empty.
fn data_arg(text : String) -> DataArg? {
  let name = StringBuilder()
  let file = StringBuilder()
  let mut split = false
  for c in text {
    if split {
      file.write_char(c)
    } else if c == '=' {
      split = true
    } else {
      name.write_char(c)
    }
  }
  let (name, file) = (name.to_string(), file.to_string())
  if split && name != "" && file != "" {
    Some({ name, file, })
  } else {
    None
  }
}

///|
/// How many inputs of `query` read stdin: the statements (no `-e` and no
/// file, or the file `-`), `--env -` and each `--data NAME=-`.
fn query_stdin_readers(m : @argparse.Matches) -> Int32 {
  let statements = if stdin_wanted(m) { 1 } else { 0 }
  let envs = m.values.get("env").unwrap_or([]).filter(f => f == "-").length()
  let datas = m.values
    .get("data")
    .unwrap_or([])
    .filter(t => data_arg(t) is Some({ file: "-", .. }))
    .length()
  statements + envs + datas
}

///|
/// Whether `query` reads stdin, so that `main` reads it first. A run that
/// ends in a usage error (a bad `--data` value, two stdin readers) reads
/// nothing, so it never waits for stdin.
fn query_reads_stdin(m : @argparse.Matches) -> Bool {
  data_args(m) is Ok(_) && query_stdin_readers(m) == 1
}

///|
/// The `--data` arguments, or the text of the usage error: a value that is
/// not `NAME=FILE`, or a name given twice.
fn data_args(m : @argparse.Matches) -> Result[Array[DataArg], String] {
  let datas : Array[DataArg] = []
  for text in m.values.get("data").unwrap_or([]) {
    match data_arg(text) {
      Some(d) => {
        if datas.iter().any(seen => seen.name == d.name) {
          return Err("--data binds \{d.name} twice")
        }
        datas.push(d)
      }
      None => return Err("--data needs NAME=FILE, found '\{text}'")
    }
  }
  Ok(datas)
}

///|
/// The decoded top-level values of the Ion file `file` (`-` is stdin), or
/// `None` after an error in `errors`.
fn read_values(
  file : String,
  io : Io,
  errors : StringBuilder,
) -> Array[@value.Value]? {
  let label = if file == "-" { "<stdin>" } else { file }
  let report = (message : String) => {
    errors.write_string("partiql query: \{label}: \{message}\n")
  }
  let text = try {
    if file == "-" {
      (io.read_stdin)()
    } else {
      (io.read_file)(file)
    }
  } catch {
    e => {
      report(error_text(e))
      return None
    }
  }
  let ions = @text.read_ion_datagram(text) catch {
    e => {
      report(e.message())
      return None
    }
  }
  let values : Array[@value.Value] = []
  for ion in ions {
    let value = @partiql_ion.from_ion(ion) catch {
      Unsupported(message) | Malformed(message) => {
        report(message)
        return None
      }
    }
    values.push(value)
  }
  Some(values)
}

///|
/// The globals of `--env` and `--data` (spec M4e §4): the fields of each
/// `--env` struct, then each `--data` binding, in order. A name bound twice
/// (exact comparison) is an error in `errors`.
fn load_bindings(
  envs : Array[String],
  datas : Array[DataArg],
  io : Io,
  errors : StringBuilder,
) -> Array[(String, @value.Value)] {
  let globals : Array[(String, @value.Value)] = []
  let bind = (file : String, name : String, value : @value.Value) => {
    if globals.iter().any(g => g.0 == name) {
      let label = if file == "-" { "<stdin>" } else { file }
      errors.write_string(
        "partiql query: \{label}: the global \{name} is bound twice\n",
      )
    } else {
      globals.push((name, value))
    }
  }
  for file in envs {
    guard read_values(file, io, errors) is Some(values) else { continue }
    match values {
      [Tuple(t)] =>
        for field in t.fields() {
          bind(file, field.0, field.1)
        }
      _ => {
        let label = if file == "-" { "<stdin>" } else { file }
        errors.write_string(
          "partiql query: \{label}: --env needs one Ion struct\n",
        )
      }
    }
  }
  for d in datas {
    guard read_values(d.file, io, errors) is Some(values) else { continue }
    let value : @value.Value = match values {
      [v] => v
      _ => Bag(@value.Bag::new(values))
    }
    bind(d.file, d.name, value)
  }
  globals
}
