// The command line's grammar, declared with `moonbitlang/core/argparse`.
// argparse's own help and version handling writes to the process stdout and
// exits the process, so the command line declares its own `--help`,
// `--version` and `help`, and `run` returns the output. See the gap table in
// AGENTS.md ("CLI").

///|
/// The commands, in the order help lists them.
let command_names : Array[String] = [
  "parse", "check", "format", "version", "help",
]

///|
/// The command `name`. `prefix` goes before the name in its usage line:
/// `""` inside the root command, `"partiql "` when its help is shown alone.
fn command(name : String, prefix : String) -> @argparse.Command {
  let named = prefix + name
  match name {
    "format" =>
      @argparse.Command(
        named,
        about="Print PartiQL in a readable layout, keeping comments.",
        flags=[
          @argparse.FlagArg(
            "write",
            short='w',
            about="Rewrite the files in place instead of printing them.",
          ),
          @argparse.FlagArg(
            "compact",
            about="Print each statement on one line (the canonical form).",
          ),
        ],
        options=[
          ..input_options(),
          @argparse.OptionArg(
            "width",
            about="Fit the layout to this line width (default 80).",
          ),
        ],
        positionals=input_positionals(),
      )
    "parse" =>
      @argparse.Command(
        named,
        about="Print the syntax tree of PartiQL as S-expressions.",
        options=input_options(),
        positionals=input_positionals(),
      )
    "check" =>
      @argparse.Command(
        named,
        about="Check that PartiQL parses; print errors only.",
        options=input_options(),
        positionals=input_positionals(),
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
    options=[
      @argparse.OptionArg(
        "color",
        about="Colour in error output: auto, always or never.",
        global=true,
      ),
    ],
    subcommands=command_names.map(name => command(name, "")),
  )
}

///|
/// Example lines for the help of the command line (`[]`) or of one command.
fn examples(path : ArrayView[String]) -> Array[String] {
  match path {
    [] =>
      [
        "partiql check query.sql", "partiql parse -e 'select a from t'", "partiql format query.sql",
        "partiql help format",
      ]
    ["parse"] =>
      [
        "partiql parse query.sql", "partiql parse -e 'select a from t'", "cat query.sql | partiql parse",
      ]
    ["check"] =>
      [
        "partiql check *.sql", "partiql check -e 'select a from t'", "partiql --color=always check query.sql",
      ]
    ["format"] =>
      [
        "partiql format query.sql", "partiql format --write *.sql", "partiql format -e 'select a from t'",
        "partiql format --width 100 query.sql", "partiql format --compact query.sql",
        "cat query.sql | partiql format",
      ]
    ["version"] => ["partiql version", "partiql --version"]
    ["help"] => ["partiql help", "partiql help version"]
    _ => []
  }
}

///|
fn input_options() -> Array[@argparse.OptionArg] {
  [
    @argparse.OptionArg(
      "expr",
      short='e',
      about="Use this statement instead of files or stdin.",
      allow_hyphen_values=true,
    ),
  ]
}

///|
fn input_positionals() -> Array[@argparse.PositionArg] {
  [
    @argparse.PositionArg(
      "file",
      about="Files to read; '-' or none reads stdin.",
      num_args=@argparse.ValueRange(lower=0),
      allow_hyphen_values=true,
    ),
  ]
}
