///|
fn query_io(files : Map[String, String], stdin~ : String = "") -> @cli.Io {
  {
    read_file: path => {
      match files.get(path) {
        Some(text) => text
        None => raise Failure("no such file: \{path}")
      }
    },
    write_file: (_, _) => fail("query never writes files"),
    read_stdin: () => stdin,
    color_default: false,
  }
}

///|
fn query(args : Array[String], io~ : @cli.Io = query_io({})) -> @cli.Outcome {
  @cli.run(["query", ..args], io~)
}

///|
test "query prints each result as Ion" {
  @expect.expect_all(soft => {
    soft
    .expect(query(["-e", "SELECT VALUE x * 2 FROM <<1, 2>> AS x"]))
    .to_equal({ stdout: "$bag::[\n  2,\n  4\n]\n", stderr: "", status: 0, })
    soft
    .expect(
      query(["--compact", "-e", "SELECT VALUE x * 2 FROM <<1, 2>> AS x"]).stdout,
    )
    .to_equal("$bag::[2, 4]\n")
    soft.expect(query(["-e", "MISSING"]).stdout).to_equal("$missing::null\n")
    soft
    .expect(query(["--compact", "-e", "1; [1, 2]; {'a': 1.50}"]).stdout)
    .to_equal("1\n[1, 2]\n{a: 150d-2}\n")
    soft
    .expect(
      query(
        ["q.sql"],
        io=query_io({ "q.sql": "SELECT VALUE 1 FROM <<0>> AS x" }),
      ).stdout,
    )
    .to_equal("$bag::[\n  1\n]\n")
    soft.expect(query([], io=query_io({}, stdin="2")).stdout).to_equal("2\n")
    // Review focus 3: no statement prints nothing.
    soft
    .expect(query(["-e", ""]))
    .to_equal({ stdout: "", stderr: "", status: 0, })
    soft
    .expect(query(["e.sql"], io=query_io({ "e.sql": "" })))
    .to_equal({ stdout: "", stderr: "", status: 0, })
  })
}

///|
test "query modes: MISSING in permissive mode, an error in strict mode" {
  @expect.expect_all(soft => {
    soft
    .expect(query(["-e", "1 + 'a'"]))
    .to_equal({ stdout: "$missing::null\n", stderr: "", status: 0, })
    soft
    .expect(query(["--strict", "-e", "1 + 'a'"]))
    .to_equal({
      stdout: "",
      stderr: (
        #|error: type error: arithmetic on a value that is not a number
        #| --> <expr>:1:1
        #|  |
        #|1 | 1 + 'a'
        #|  | ^^^^^^^
        #|
      ),
      status: 1,
    })
  })
}

///|
test "query stops at the first failing statement and keeps earlier output" {
  let outcome = query(["-e", "1; 1 / 0; 3"])
  @expect.expect_all(soft => {
    soft.expect(outcome.status).to_equal(1)
    soft.expect(outcome.stdout).to_equal("1\n")
    soft
    .expect(outcome.stderr)
    .to_equal(
      (
        #|error: data error: division by zero
        #| --> <expr>:1:4
        #|  |
        #|1 | 1; 1 / 0; 3
        #|  |    ^^^^^
        #|
      ),
    )
    // Review focus 2: CRLF line breaks; the error is on line 2.
    soft
    .expect(query(["c.sql"], io=query_io({ "c.sql": "1;\r\n1 / 0" })).stderr)
    .to_contain(" --> c.sql:2:1")
    // An unsupported form prints its message as is (plan ruling 2).
    soft
    .expect(query(["-e", "?"]))
    .to_equal({
      stdout: "",
      stderr: "error: a parameter (later) is not supported yet\n --> <expr>:1:1\n  |\n1 | ?\n  | ^\n",
      status: 1,
    })
  })
}

///|
test "query evaluates nothing when an input does not parse" {
  let io = query_io({ "good.sql": "1", "bad.sql": "select from t" })
  let outcome = query(["good.sql", "bad.sql"], io~)
  @expect.expect_all(soft => {
    soft.expect(outcome.status).to_equal(1)
    soft.expect(outcome.stdout).to_equal("")
    soft
    .expect(outcome.stderr)
    .to_contain("error: expected an expression, found keyword `from`")
    soft.expect(outcome.stderr).to_contain(" --> bad.sql:1:8")
    let missing = query(["good.sql", "missing.sql"], io~)
    soft.expect(missing.status).to_equal(1)
    soft.expect(missing.stdout).to_equal("")
    soft
    .expect(missing.stderr)
    .to_equal("partiql query: missing.sql: no such file: missing.sql\n")
  })
}

///|
test "query help and usage" {
  @expect.expect_all(soft => {
    let help = @cli.run(["help", "query"])
    soft.expect(help.status).to_equal(0)
    soft.expect(help.stdout).to_contain("Usage: partiql query")
    soft.expect(help.stdout).to_contain("--strict")
    soft.expect(help.stdout).to_contain("--compact")
    soft.expect(help.stdout).to_contain("--env <env>")
    soft.expect(help.stdout).to_contain("--data <data>")
    soft.expect(help.stdout).to_contain("Examples:")
    soft
    .expect(@cli.run(["query", "-h"]).stdout)
    .to_contain("Usage: partiql query")
    soft
    .expect(query(["-e", "1", "a.sql"], io=query_io({ "a.sql": "1" })).status)
    .to_equal(2)
    // `-e` without a value. (An unknown option reads as a file name: bead
    // partiql-sfz.6.)
    soft.expect(query(["-e"]).status).to_equal(2)
  })
}
