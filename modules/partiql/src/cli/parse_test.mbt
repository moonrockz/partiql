///|
fn io_with(
  files : Map[String, String],
  stdin? : String = "",
  color? : Bool = false,
) -> @cli.Io {
  {
    read_file: path => {
      match files.get(path) {
        Some(text) => text
        None => raise Failure("no such file: \{path}")
      }
    },
    write_file: (_, _) => (),
    read_stdin: () => stdin,
    color_default: color,
  }
}

///|
test "parse prints S-expressions" {
  let io = io_with({
    "a.sql": "select a from t; select 1",
    "b.sql": "select b from u",
  })
  @expect.expect_all(soft => {
    soft
    .expect(@cli.run(["parse", "-e", "select a from t"], io~).stdout)
    .to_equal("(select a (from t))\n")
    soft
    .expect(@cli.run(["parse", "a.sql"], io~).stdout)
    .to_equal("(select a (from t))\n(select 1)\n")
    soft
    .expect(@cli.run(["parse", "a.sql", "b.sql"], io~).stdout)
    .to_equal(
      ";; a.sql\n(select a (from t))\n(select 1)\n;; b.sql\n(select b (from u))\n",
    )
    soft
    .expect(@cli.run(["parse"], io=io_with(Map([]), stdin="select 2")).stdout)
    .to_equal("(select 2)\n")
  })
}

///|
test "check reports errors and keeps going" {
  let io = io_with({ "good.sql": "select 1", "bad.sql": "select from t" })
  let outcome = @cli.run(["check", "good.sql", "bad.sql", "missing.sql"], io~)
  @expect.expect_all(soft => {
    soft.expect(outcome.status).to_equal(1)
    soft.expect(outcome.stdout).to_equal("")
    soft
    .expect(
      outcome.stderr.contains(
        "error: expected an expression, found keyword `from`",
      ),
    )
    .to_be_true()
    soft.expect(outcome.stderr.contains(" --> bad.sql:1:8")).to_be_true()
    soft
    .expect(outcome.stderr.contains("missing.sql: no such file: missing.sql"))
    .to_be_true()
    soft
    .expect(@cli.run(["check", "good.sql"], io~))
    .to_equal({ stdout: "", stderr: "", status: 0, })
    soft
    .expect(
      @cli.run(["check", "-e", "insert into t value 1"], io~).stderr.contains(
        "INSERT statements are not supported yet",
      ),
    )
    .to_be_true()
  })
}

///|
test "colour follows --color and the terminal default" {
  let source = Map([("bad.sql", "select from t")])
  @expect.expect_all(soft => {
    soft
    .expect(
      @cli.run(["check", "bad.sql"], io=io_with(source, color=true)).stderr.contains(
        "\u{1b}[",
      ),
    )
    .to_be_true()
    soft
    .expect(
      @cli.run(["check", "bad.sql"], io=io_with(source)).stderr.contains(
        "\u{1b}[",
      ),
    )
    .to_be_false()
    soft
    .expect(
      @cli.run(["--color", "always", "check", "bad.sql"], io=io_with(source)).stderr.contains(
        "\u{1b}[",
      ),
    )
    .to_be_true()
    soft
    .expect(
      @cli.run(
        ["check", "--color", "never", "bad.sql"],
        io=io_with(source, color=true),
      ).stderr.contains("\u{1b}["),
    )
    .to_be_false()
    soft
    .expect(
      @cli.run(["--color", "blue", "check", "bad.sql"], io=io_with(source)).status,
    )
    .to_equal(2)
  })
}

///|
test "parse and check usage, help and stdin" {
  let io = io_with(Map([]))
  @expect.expect_all(soft => {
    soft.expect(@cli.run(["parse", "-e", "x", "a.sql"], io~).status).to_equal(2)
    soft.expect(@cli.run(["check", "-", "a.sql"], io~).status).to_equal(2)
    soft.expect(@cli.run(["help", "parse"]).stdout).to_contain("Examples:")
    soft.expect(@cli.run(["help", "check"]).stdout).to_contain("Examples:")
    soft.expect(@cli.reads_stdin(["parse"])).to_be_true()
    soft.expect(@cli.reads_stdin(["check", "-"])).to_be_true()
    soft.expect(@cli.reads_stdin(["check", "a.sql"])).to_be_false()
    soft.expect(@cli.reads_stdin(["parse", "--help"])).to_be_false()
  })
}

///|
/// The number of rendered diagnostics in `stderr`.
fn diagnostics(stderr : String) -> Int {
  stderr.split("\n").filter(line => line.has_prefix("error:")).count()
}

///|
test "check and parse report every error" {
  let (io, _) = fake_io({
    "bad.sql": "SELECT a, , b FROM t;\nSELECT 1 FROM WHERE x;\nSELECT 1",
  })
  @expect.expect_all(soft => {
    let checked = @cli.run(["check", "bad.sql"], io~)
    soft.expect(checked.status).to_equal(1)
    soft.expect(diagnostics(checked.stderr)).to_equal(2)
    let parsed = @cli.run(["parse", "bad.sql"], io~)
    soft.expect(parsed.status).to_equal(1)
    soft.expect(diagnostics(parsed.stderr)).to_equal(2)
    soft.expect(parsed.stdout).to_contain("(error)")
    soft.expect(parsed.stdout).to_contain("(select 1)")
  })
}
