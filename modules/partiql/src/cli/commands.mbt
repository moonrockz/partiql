// The command line's grammar, declared with `moonbitlang/core/argparse`.
// argparse's own help and version handling writes to the process stdout and
// exits the process, so the command line declares its own `--help`,
// `--version` and `help`, and `run` returns the output. See the gap table in
// AGENTS.md ("CLI").

///|
/// The commands, in the order help lists them.
let command_names : Array[String] = ["format", "version", "help"]

///|
/// The command `name`. `prefix` goes before the name in its usage line:
/// `""` inside the root command, `"partiql "` when its help is shown alone.
fn command(name : String, prefix : String) -> @argparse.Command {
  let named = prefix + name
  match name {
    "format" =>
      @argparse.Command(
        named,
        about="Print PartiQL in canonical form, keeping comments.",
        flags=[
          @argparse.FlagArg(
            "write",
            short='w',
            about="Rewrite the files in place instead of printing them.",
          ),
        ],
        options=[
          @argparse.OptionArg(
            "expr",
            short='e',
            about="Format this statement instead of files or stdin.",
            allow_hyphen_values=true,
          ),
        ],
        positionals=[
          @argparse.PositionArg(
            "file",
            about="Files to format; '-' or none reads stdin.",
            num_args=@argparse.ValueRange(lower=0),
            allow_hyphen_values=true,
          ),
        ],
      )
    "version" => @argparse.Command(named, about="Print the version.")
    _ =>
      @argparse.Command(
        named,
        about="Print help for the command line or for one command.",
        positionals=[
          @argparse.PositionArg(
            "command",
            about="The command to describe.",
            num_args=@argparse.ValueRange(lower=0, upper=1),
          ),
        ],
      )
  }
}

///|
fn command_line() -> @argparse.Command {
  @argparse.Command(
    "partiql",
    about="Tools for PartiQL, the SQL-compatible query language for nested and semi-structured data.",
    disable_help_flag=true,
    disable_help_subcommand=true,
    disable_version_flag=true,
    flags=[
      @argparse.FlagArg(
        "help",
        short='h',
        about="Show help information.",
        global=true,
      ),
      @argparse.FlagArg("version", short='V', about="Show the version."),
    ],
    subcommands=command_names.map(name => command(name, "")),
  )
}

///|
/// Example lines for the help of the command line (`[]`) or of one command.
fn examples(path : ArrayView[String]) -> Array[String] {
  match path {
    [] => ["partiql format query.sql", "partiql version", "partiql help format"]
    ["format"] =>
      [
        "partiql format query.sql", "partiql format --write *.sql", "partiql format -e 'select a from t'",
        "cat query.sql | partiql format",
      ]
    ["version"] => ["partiql version", "partiql --version"]
    ["help"] => ["partiql help", "partiql help version"]
    _ => []
  }
}
