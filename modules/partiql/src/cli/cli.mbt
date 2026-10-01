///|
/// The result of one run: text for each stream and the exit status.
pub(all) struct Outcome {
  stdout : String
  stderr : String
  status : Int
} derive(Debug, Eq)

///|
fn success(text : String) -> Outcome {
  { stdout: text, stderr: "", status: 0, }
}

///|
fn usage_error(text : String) -> Outcome {
  { stdout: "", stderr: text, status: 2, }
}

///|
fn help_outcome(path : ArrayView[String]) -> Outcome {
  match help_text(path) {
    Some(text) => success(text)
    None => {
      let name = path.iter().collect().join(" ")
      usage_error(
        "partiql: unknown command: \{name}\nRun 'partiql help' for more information.\n",
      )
    }
  }
}

///|
/// Runs the command line. `args` excludes the program name.
pub fn run(args : ArrayView[String]) -> Outcome {
  if args.is_empty() {
    return usage_error(help_text([]).unwrap_or(""))
  }
  if help_request(args) is Some(path) {
    return help_outcome(path)
  }
  let matches = command_line().parse(argv=args, env={}) catch {
    error => return usage_error(short_error(error.to_string()))
  }
  if matches.flags.get("version") == Some(true) {
    return success("partiql \{version}\n")
  }
  match matches.subcommand {
    Some(("version", _)) => success("partiql \{version}\n")
    Some(("help", sub)) => help_outcome(sub.values.get("command").unwrap_or([]))
    Some((name, _)) => usage_error("partiql: command not handled: \{name}\n")
    None => usage_error(help_text([]).unwrap_or(""))
  }
}
