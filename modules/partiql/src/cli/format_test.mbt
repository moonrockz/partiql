///|
/// A fake file system and stdin.
fn fake_io(
  files : Map[String, String],
  stdin? : String = "",
) -> (@cli.Io, Map[String, String]) {
  let written : Map[String, String] = Map([])
  let io : @cli.Io = {
    read_file: path => {
      match files.get(path) {
        Some(text) => text
        None => raise Failure("no such file: \{path}")
      }
    },
    write_file: (path, text) => written.set(path, text),
    read_stdin: () => stdin,
    color_default: false,
  }
  (io, written)
}

///|
test "format a statement argument" {
  let (io, _) = fake_io(Map([]))
  @expect.expect(@cli.run(["format", "-e", "select a from t"], io~)).to_equal({
    stdout: "SELECT a FROM t;\n",
    stderr: "",
    status: 0,
  })
}

///|
test "format files and stdin" {
  let (io, written) = fake_io(
    { "a.sql": "select 1", "b.sql": "-- b\nselect 2" },
    stdin="select 3",
  )
  @expect.expect_all(soft => {
    soft
    .expect(@cli.run(["format", "a.sql"], io~).stdout)
    .to_equal("SELECT 1;\n")
    soft
    .expect(@cli.run(["format", "a.sql", "b.sql"], io~).stdout)
    .to_equal("-- a.sql\nSELECT 1;\n-- b.sql\n-- b\nSELECT 2;\n")
    soft.expect(@cli.run(["format"], io~).stdout).to_equal("SELECT 3;\n")
    soft.expect(@cli.run(["format", "-"], io~).stdout).to_equal("SELECT 3;\n")
    let outcome = @cli.run(["format", "--write", "a.sql", "b.sql"], io~)
    soft.expect(outcome).to_equal({ stdout: "", stderr: "", status: 0, })
    soft.expect(written.get("a.sql")).to_equal(Some("SELECT 1;\n"))
    soft.expect(written.get("b.sql")).to_equal(Some("-- b\nSELECT 2;\n"))
  })
}

///|
test "format reports parse errors with the position and keeps going" {
  let (io, _) = fake_io({
    "good.sql": "select 1",
    "bad.sql": "select 1;\nselect 2;\nselect from",
  })
  let outcome = @cli.run(["format", "bad.sql", "good.sql"], io~)
  @expect.expect_all(soft => {
    soft.expect(outcome.status).to_equal(1)
    soft.expect(outcome.stderr.has_prefix("error: ")).to_be_true()
    soft.expect(outcome.stderr.contains(" --> bad.sql:3:8")).to_be_true()
    soft.expect(outcome.stdout).to_equal("-- good.sql\nSELECT 1;\n")
    soft.expect(@cli.run(["format", "missing.sql"], io~).status).to_equal(1)
    soft
    .expect(@cli.run(["format", "missing.sql"], io~).stderr)
    .to_equal("partiql format: missing.sql: no such file: missing.sql\n")
    soft
    .expect(
      @cli.run(["format", "-e", "select from"], io~).stderr.contains(
        " --> <expr>:1:8",
      ),
    )
    .to_be_true()
  })
}

///|
test "format usage errors" {
  let (io, _) = fake_io({ "a.sql": "select 1" })
  @expect.expect_all(soft => {
    for
      args in [
        ["format", "-e", "select 1", "a.sql"],
        ["format", "--write", "-e", "select 1"],
        ["format", "--write"],
        ["format", "-", "a.sql"],
      ] {
      soft.expect(@cli.run(args, io~).status, label=args.join(" ")).to_equal(2)
    }
  })
}

///|
test "format help and stdin detection" {
  @expect.expect_all(soft => {
    let help = @cli.run(["help", "format"])
    soft.expect(help.status).to_equal(0)
    soft.expect(help.stdout).to_contain("partiql format")
    soft.expect(help.stdout).to_contain("Examples:")
    soft.expect(help.stdout).to_contain("--width <width>")
    soft.expect(help.stdout).to_contain("--compact")
    soft.expect(@cli.reads_stdin(["format"])).to_be_true()
    soft.expect(@cli.reads_stdin(["format", "-"])).to_be_true()
    soft.expect(@cli.reads_stdin(["format", "a.sql"])).to_be_false()
    soft.expect(@cli.reads_stdin(["format", "-e", "x"])).to_be_false()
    soft.expect(@cli.reads_stdin(["version"])).to_be_false()
    for
      args in [
        ["format", "--help"],
        ["format", "-h"],
        ["--help", "format"],
        ["help", "format"],
        ["format", "--write"],
        ["format", "--write", "-"],
      ] {
      soft.expect(@cli.reads_stdin(args), label=args.join(" ")).to_be_false()
    }
  })
}

///|
test "format widths and compact output" {
  let long = "select a, b, c from t where x = 1 and y = 2"
  let wide = "select aaaaaaaaaa, bbbbbbbbbb, cccccccccc, dddddddddd from tttttttttt where xxxxxxxxxx = 1"
  let (io, written) = fake_io({ "q.sql": long })
  @expect.expect_all(soft => {
    soft
    .expect(@cli.run(["format", "-e", long], io~).stdout)
    .to_equal("SELECT a, b, c FROM t WHERE x = 1 AND y = 2;\n")
    soft
    .expect(@cli.run(["format", "-e", wide], io~).stdout)
    .to_equal(
      "SELECT aaaaaaaaaa, bbbbbbbbbb, cccccccccc, dddddddddd\nFROM tttttttttt\nWHERE xxxxxxxxxx = 1;\n",
    )
    soft
    .expect(@cli.run(["format", "--compact", "-e", wide], io~).stdout)
    .to_equal(
      "SELECT aaaaaaaaaa, bbbbbbbbbb, cccccccccc, dddddddddd FROM tttttttttt WHERE xxxxxxxxxx = 1;\n",
    )
    soft
    .expect(@cli.run(["format", "--width", "30", "-e", long], io~).stdout)
    .to_equal("SELECT a, b, c\nFROM t\nWHERE x = 1 AND y = 2;\n")
    soft
    .expect(@cli.run(["format", "--width", "1", "-e", "select a"], io~).stdout)
    .to_equal("SELECT\n  a;\n")
    soft
    .expect(
      @cli.run(["format", "--compact", "-e", "select a, -- c\n b from t"], io~).stdout,
    )
    .to_equal("SELECT a, -- c\nb FROM t;\n")
    ignore(@cli.run(["format", "--write", "--width", "20", "q.sql"], io~))
    soft
    .expect(written.get("q.sql"))
    .to_equal(Some("SELECT a, b, c\nFROM t\nWHERE x = 1\n  AND y = 2;\n"))
  })
}

///|
test "format width usage errors" {
  let (io, _) = fake_io(Map([]))
  @expect.expect_all(soft => {
    soft
    .expect(
      @cli.run(["format", "--compact", "--width", "30", "-e", "select a"], io~),
    )
    .to_equal({
      stdout: "",
      stderr: "partiql format: --compact takes no --width\nRun 'partiql help format' for more information.\n",
      status: 2,
    })
    soft
    .expect(@cli.run(["format", "--width", "0", "-e", "select a"], io~))
    .to_equal({
      stdout: "",
      stderr: "partiql format: --width must be a whole number of at least 1\nRun 'partiql help format' for more information.\n",
      status: 2,
    })
    soft
    .expect(@cli.run(["format", "--width", "x", "-e", "select a"], io~).stderr)
    .to_equal(
      "partiql format: --width must be a whole number of at least 1\nRun 'partiql help format' for more information.\n",
    )
    soft
    .expect(@cli.run(["format", "--width", "-3", "-e", "select a"], io~).status)
    .to_equal(2)
  })
}

///|
test "format reports every error and writes nothing" {
  let (io, written) = fake_io({
    "bad.sql": "SELECT a, , b FROM t; SELECT 1 FROM WHERE x",
    "ok.sql": "select 1",
  })
  let outcome = @cli.run(["format", "--write", "bad.sql", "ok.sql"], io~)
  @expect.expect_all(soft => {
    soft.expect(outcome.status).to_equal(1)
    soft
    .expect(
      outcome.stderr
      .split("\n")
      .filter(line => line.has_prefix("error:"))
      .count(),
    )
    .to_equal(2)
    soft.expect(written.get("bad.sql")).to_equal(None)
    soft.expect(written.get("ok.sql")).to_equal(Some("SELECT 1;\n"))
  })
}
