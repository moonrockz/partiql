///|
let version_line : String = "partiql \{@cli.version}\n"

///|
test "version command and flags print the version" {
  for args in [["version"], ["--version"], ["-V"]] {
    @expect.expect(@cli.run(args), label=args.join(" ")).to_equal({
      stdout: version_line,
      stderr: "",
      status: 0,
    })
  }
}

///|
test "root help from the flag, the short flag and the command" {
  for args in [["--help"], ["-h"], ["help"]] {
    let outcome = @cli.run(args)
    @expect.expect(outcome.status, label=args.join(" ")).to_equal(0)
    @expect.expect(outcome.stderr, label=args.join(" ")).to_equal("")
    @expect.expect(outcome.stdout, label=args.join(" ")).to_contain(
      "Usage: partiql [options] [command]",
    )
    @expect.expect(outcome.stdout, label=args.join(" ")).to_contain("Examples:")
  }
}

///|
test "command help has the partiql prefix in its usage line" {
  for args in [["help", "version"], ["version", "--help"], ["version", "-h"]] {
    let outcome = @cli.run(args)
    @expect.expect(outcome.status, label=args.join(" ")).to_equal(0)
    @expect.expect(outcome.stdout, label=args.join(" ")).to_contain(
      "Usage: partiql version",
    )
  }
}

///|
test "help for an unknown command is a usage error" {
  let outcome = @cli.run(["help", "frobnicate"])
  @expect.expect(outcome.status).to_equal(2)
  @expect.expect(outcome.stdout).to_equal("")
  @expect.expect(outcome.stderr).to_contain("unknown command: frobnicate")
}

///|
test "no arguments prints the root help to stderr with status 2" {
  let outcome = @cli.run([])
  @expect.expect(outcome.status).to_equal(2)
  @expect.expect(outcome.stdout).to_equal("")
  @expect.expect(outcome.stderr).to_contain(
    "Usage: partiql [options] [command]",
  )
}

///|
test "an unknown command gives a short error with a hint" {
  let outcome = @cli.run(["frobnicate"])
  @expect.expect(outcome.status).to_equal(2)
  @expect.expect(outcome.stderr).to_contain(
    "partiql: unexpected value 'frobnicate'",
  )
  @expect.expect(outcome.stderr).to_contain(
    "Usage: partiql [options] [command]",
  )
  @expect.expect(outcome.stderr).to_contain(
    "Run 'partiql help' for more information.",
  )
  // The short error leaves out the full help text.
  @expect.expect(outcome.stderr).not().to_contain("Commands:")
}

///|
test "an unknown option is a usage error" {
  let outcome = @cli.run(["--nope"])
  @expect.expect(outcome.status).to_equal(2)
  @expect.expect(outcome.stderr).to_contain("unexpected argument '--nope'")
}

///|
test "root help snapshot" {
  inspect(
    @cli.run(["--help"]).stdout,
    content=(
      #|Usage: partiql [options] [command]
      #|
      #|Tools for PartiQL, the SQL-compatible query language for nested and semi-structured data.
      #|
      #|Commands:
      #|  version  Print the version.
      #|  help     Print help for the command line or for one command.
      #|
      #|Options:
      #|  -h, --help     Show help information.
      #|  -V, --version  Show the version.
      #|
      #|Examples:
      #|  partiql version
      #|  partiql help version
      #|
    ),
  )
}
