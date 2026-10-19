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
  let text = base.trim_end(chars="\n").to_owned() + "\n"
  Some(
    text + section("Examples", examples(path)) + section("Notes", notes(path)),
  )
}

///|
/// A titled block of indented lines, or nothing when there are none.
fn section(title : String, lines : Array[String]) -> String {
  if lines.is_empty() {
    ""
  } else {
    "\n\{title}:\n" + lines.map(line => "  " + line + "\n").join("")
  }
}

///|
/// Facts about a command that its options do not show.
fn notes(path : ArrayView[String]) -> Array[String] {
  match path {
    ["query"] =>
      [
        "Ion input is text or binary, detected by the binary version marker.", "Ion --data binds 0 elements as an empty bag, 1 as-is, and many as a bag.",
        "--each NAME runs the script for each element in order; empty data runs nothing.",
        "JSON input is one JSON document per file; --env requires an object.", "JSON --each iterates a top-level array, or runs once for any other document.",
        "JSON output writes one document per result; --compact makes JSON Lines.",
        "JSON keeps integer precision, decimal scale and duplicate object keys.",
        "Finite floats write binary64 spellings and read back as Int/Decimal.", "JSON rejects non-finite floats, MISSING, bags, maps, graphs, temporals,",
        "intervals, blobs, clobs and boxed Ion. CAST a SELECT result AS LIST explicitly.",
        "JSON input cannot use Ion Schema options. Ion remains the default.", "--output-format binary writes raw bytes; --compact applies only to text.",
        "Schemas validate raw PartiQL-encoded Ion before any statement runs.", "The session time zone is UTC: CURRENT_DATE, CURRENT_TIME and",
        "CURRENT_TIMESTAMP read the system clock at offset +00:00.",
      ]
    _ => []
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
