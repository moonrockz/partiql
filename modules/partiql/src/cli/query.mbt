// `partiql query` (spec M4e): evaluates statements against global bindings
// read from Ion, JSON or YAML, and prints each result in the selected format.

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
  if query_options_error(m, datas) is Some(message) {
    return usage(message)
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
  let loaded = load_bindings(m, datas, io, errors)
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
  let env = @eval.Bindings::of_pairs(loaded.globals)
  let mode : @eval.Mode = if m.flags.get("strict") == Some(true) {
    Strict
  } else {
    Permissive
  }
  let compact = m.flags.get("compact") == Some(true)
  let binary = m.values.get("output-format") == Some(["binary"])
  let json = m.values.get("output-format") == Some(["json"])
  let results : Array[@value.Value] = []
  let done = () => {
    if binary {
      let bytes = @partiql_ion.write_bytes(results) catch {
        e => {
          errors.write_string("partiql query: " + e.message() + "\n")
          return finish(out, errors)
        }
      }
      { ..finish(out, errors), stdout_bytes: Some(bytes), }
    } else {
      finish(out, errors)
    }
  }
  for script in scripts {
    let (input, statements) = script
    let environments = match loaded.each {
      Some((name, values)) =>
        values.iter().map(value => env.with_value(name, value))
      None => [env].iter()
    }
    for env in environments {
      for statement in statements {
        let value = @eval.evaluate(statement, env~, mode~, clock?=io.clock) catch {
          e => {
            errors.write_string(eval_error_text(e, input, color))
            return done()
          }
        }
        if binary {
          results.push(value)
        } else {
          let text = try {
            if json {
              (@partiql_json.write_text(value, pretty=!compact) catch {
                e => raise Failure(e.message())
              }) +
              "\n"
            } else {
              @partiql_ion.write_text([value], pretty=!compact) catch {
                e => raise Failure(e.message())
              }
            }
          } catch {
            e => {
              errors.write_string(
                "partiql query: \{input.name}: " + error_text(e) + "\n",
              )
              return done()
            }
          }
          out.write_string(text)
        }
      }
    }
  }
  done()
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
  let schemas = m.values
    .get("env-schema")
    .unwrap_or([])
    .filter(f => f == "-")
    .length() +
    m.values
    .get("data-schema")
    .unwrap_or([])
    .filter(t => data_arg(t) is Some({ file: "-", .. }))
    .length()
  statements + envs + datas + schemas
}

///|
/// Whether `query` reads stdin, so that `main` reads it first. A run that
/// ends in a usage error (a bad `--data` value, two stdin readers) reads
/// nothing, so it never waits for stdin.
fn query_reads_stdin(m : @argparse.Matches) -> Bool {
  data_args(m) is Ok(datas) &&
  query_options_error(m, datas) is None &&
  query_stdin_readers(m) == 1
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
fn ion_error_text(e : @partiql_ion.IonDataError) -> String {
  match e {
    Text(e) => e.message()
    Codec(Unsupported(message)) | Codec(Malformed(message)) => message
    _ => e.message()
  }
}

///|
fn read_ion_file(file : String, io : Io) -> Bytes raise {
  if file == "-" {
    match io.read_stdin_bytes {
      Some(read) => read()
      None => @utf8.encode((io.read_stdin)())
    }
  } else {
    match io.read_file_bytes {
      Some(read) => read(file)
      None => @utf8.encode((io.read_file)(file))
    }
  }
}

///|
fn query_report(
  errors : StringBuilder,
  file : String,
  message : String,
) -> Unit {
  let label = if file == "-" { "<stdin>" } else { file }
  for line in message.split("\n") {
    errors.write_string("partiql query: \{label}: \{line}\n")
  }
}

///|
fn read_values(
  file : String,
  io : Io,
  errors : StringBuilder,
  validation : @partiql_ion.Validation?,
  format : InputFormat,
) -> Array[@value.Value]? {
  let bytes = read_ion_file(file, io) catch {
    e => {
      query_report(errors, file, error_text(e))
      return None
    }
  }
  let values = try {
    match format {
      Json =>
        [
          @partiql_json.read_bytes(bytes) catch {
            e => raise Failure(e.message())
          },
        ]
      Yaml =>
        @partiql_yaml.read_bytes(bytes) catch {
          e => raise Failure(e.message())
        }
      Ion =>
        @partiql_ion.read_bytes(bytes, validation?) catch {
          e => raise Failure(ion_error_text(e))
        }
    }
  } catch {
    e => {
      query_report(errors, file, error_text(e))
      return None
    }
  }
  Some(values)
}

///|
priv struct LoadedBindings {
  globals : Array[(String, @value.Value)]
  each : (String, Array[@value.Value])?
}

///|
fn read_validation(
  file : String,
  m : @argparse.Matches,
  io : Io,
  errors : StringBuilder,
) -> @partiql_ion.Validation? {
  let bytes = read_ion_file(file, io) catch {
    e => {
      query_report(errors, file, error_text(e))
      return None
    }
  }
  let schema = @partiql_ion.load_schema_bytes(bytes) catch {
    e => {
      query_report(errors, file, ion_error_text(e))
      return None
    }
  }
  let name = m.values.get("schema-type").unwrap_or(["document"])[0]
  Some(
    if m.flags.get("schema-document") == Some(true) {
      @partiql_ion.Validation::document(schema, name)
    } else {
      @partiql_ion.Validation::elements(schema, name)
    },
  )
}

///|
fn load_bindings(
  m : @argparse.Matches,
  datas : Array[DataArg],
  io : Io,
  errors : StringBuilder,
) -> LoadedBindings {
  let format = input_format(m)
  let globals : Array[(String, @value.Value)] = []
  let mut each : (String, Array[@value.Value])? = None
  let bind = (file : String, name : String, value : @value.Value) => {
    if globals.iter().any(g => g.0 == name) {
      query_report(errors, file, "the global \{name} is bound twice")
    } else {
      globals.push((name, value))
    }
  }
  let env_validation = match m.values.get("env-schema") {
    Some([file, ..]) => read_validation(file, m, io, errors)
    _ => None
  }
  let validations : Map[String, @partiql_ion.Validation] = Map([])
  for arg in m.values.get("data-schema").unwrap_or([]) {
    if data_arg(arg) is Some(d) &&
      read_validation(d.file, m, io, errors) is Some(v) {
      validations[d.name] = v
    }
  }
  if errors.to_string() != "" {
    return { globals, each, }
  }
  for file in m.values.get("env").unwrap_or([]) {
    guard read_values(file, io, errors, env_validation, format) is Some(values) else {
      continue
    }
    match values {
      [Tuple(t)] =>
        for field in t.fields() {
          bind(file, field.0, field.1)
        }
      _ =>
        query_report(
          errors,
          file,
          match format {
            Json => "--env needs one JSON object"
            Yaml => "--env needs exactly one YAML mapping document"
            Ion => "--env needs one Ion struct"
          },
        )
    }
  }
  for d in datas {
    guard read_values(d.file, io, errors, validations.get(d.name), format)
      is Some(values) else {
      continue
    }
    if m.values.get("each") == Some([d.name]) {
      each = Some(
        (
          d.name,
          if !(format is Ion) {
            match values {
              [List(items)] => items
              _ => values
            }
          } else {
            values
          },
        ),
      )
    }
    let value : @value.Value = match values {
      [v] => v
      _ => @value.Value::from_bag(@value.Bag(values))
    }
    bind(d.file, d.name, value)
  }
  { globals, each, }
}

///|
fn query_options_error(
  m : @argparse.Matches,
  datas : Array[DataArg],
) -> String? {
  match m.values.get("output-format") {
    None | Some(["ion"]) | Some(["binary"]) | Some(["json"]) => ()
    _ => return Some("--output-format must be ion, binary or json")
  }
  match m.values.get("input-format") {
    None | Some(["ion"]) => ()
    Some(["json" | "yaml" as format]) =>
      if m.values.get("env-schema") is Some(_) ||
        m.values.get("data-schema") is Some(_) ||
        m.values.get("schema-type") is Some(_) ||
        m.flags.get("schema-document") == Some(true) {
        return Some(
          "Ion Schema options cannot be used with --input-format " + format,
        )
      }
    _ => return Some("--input-format must be ion, json or yaml")
  }
  if m.values.get("each") is Some([name, ..]) && !datas.any(d => d.name == name) {
    return Some("--each needs a --data binding named " + name)
  }
  let names : Array[String] = []
  for arg in m.values.get("data-schema").unwrap_or([]) {
    guard data_arg(arg) is Some(d) else {
      return Some("--data-schema needs NAME=FILE")
    }
    if !datas.any(data => data.name == d.name) {
      return Some("--data-schema names an unknown binding: " + d.name)
    }
    if names.contains(d.name) {
      return Some("--data-schema names a binding twice: " + d.name)
    }
    names.push(d.name)
  }
  if m.values.get("env-schema") is Some(_) && m.values.get("env") is None {
    return Some("--env-schema needs --env")
  }
  if m.values.get("data-schema") is None &&
    m.values.get("env-schema") is None &&
    (
      m.values.get("schema-type") is Some(_) ||
      m.flags.get("schema-document") == Some(true)
    ) {
    return Some("--schema-type and --schema-document need a schema option")
  }
  None
}

///|
priv enum InputFormat {
  Ion
  Json
  Yaml
}

///|
// Called only after query_options_error validates the option.
fn input_format(m : @argparse.Matches) -> InputFormat {
  match m.values.get("input-format") {
    Some(["json"]) => Json
    Some(["yaml"]) => Yaml
    _ => Ion
  }
}
