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
    soft.expect(outcome.stderr.has_prefix("bad.sql:3:8: ")).to_be_true()
    soft.expect(outcome.stdout).to_equal("-- good.sql\nSELECT 1;\n")
    soft.expect(@cli.run(["format", "missing.sql"], io~).status).to_equal(1)
    soft
    .expect(@cli.run(["format", "missing.sql"], io~).stderr)
    .to_equal("partiql format: missing.sql: no such file: missing.sql\n")
    soft
    .expect(
      @cli.run(["format", "-e", "select from"], io~).stderr.has_prefix(
        "<expr>:1:8: ",
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
