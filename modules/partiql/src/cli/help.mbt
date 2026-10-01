///|
/// The help text for the command line (`[]`) or for one command, with an
/// `Examples:` block. `None` when the command does not exist.
fn help_text(path : ArrayView[String]) -> String? {
  let base = match path {
    [] => command_line().render_help()
    [name] if command_names.contains(name) =>
      command(name, "partiql ").render_help()
    _ => return None
  }
  let lines = examples(path)
  let text = base.trim_end(chars="\n").to_owned()
  if lines.is_empty() {
    Some(text + "\n")
  } else {
    Some(
      text + "\n\nExamples:\n" + lines.map(line => "  " + line + "\n").join(""),
    )
  }
}

///|
/// When the arguments ask for help (`-h` or `--help` before `--`), the
/// command they ask about: `[]` for the command line. argparse checks
/// required arguments before it sees the help flag, so the command line
/// answers help before argparse parses.
fn help_request(args : ArrayView[String]) -> Array[String]? {
  let mut asked = false
  let path : Array[String] = []
  for arg in args {
    match arg {
      "--" => break
      "-h" | "--help" => asked = true
      _ if arg.has_prefix("-") => ()
      _ if path.is_empty() => path.push(arg)
      _ => ()
    }
  }
  if asked {
    Some(path)
  } else {
    None
  }
}

///|
/// An argparse error in short form: the error line, the usage line, and a
/// hint. argparse puts the full help text in its error.
fn short_error(message : String) -> String {
  let lines = message.split("\n").map(line => line.to_owned()).collect()
  let first = lines.get(0).unwrap_or("error")
  let reason = if first.has_prefix("error: ") {
    first.view(start_offset=7).to_owned()
  } else {
    first
  }
  let usage = match lines.search_by(line => line.has_prefix("Usage: ")) {
    Some(i) => lines[i] + "\n"
    None => ""
  }
  "partiql: \{reason}\n\{usage}Run 'partiql help' for more information.\n"
}
