///|
fn query_io(
  files : Map[String, String],
  stdin~ : String = "",
  clock~ : @eval.Clock? = None,
) -> @cli.Io {
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
    clock,
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
    .to_equal("1\n[1, 2]\n{a: 1.50}\n")
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

///|
/// The outcome of a run that fails with `stderr` and prints nothing.
fn failed(stderr : String) -> @cli.Outcome {
  { stdout: "", stderr, status: 1, }
}

///|
test "query binds --data files: one value as is, other counts as a bag" {
  let io = query_io({
    "rows.ion": "{a: 1} {a: 2}",
    "list.ion": "[1, 2]",
    "one.ion": "{a: 1}",
    "empty.ion": "",
    "bag.ion": "$bag::[1]",
    "missing.ion": "$missing::null",
    "boxed.ion": "$ion::foo::1",
    "annotated.ion": "foo::1",
    "a=b.ion": "7",
  })
  let run = (data : String, statement : String) => {
    query(["--compact", "--data", data, "-e", statement], io~)
  }
  @expect.expect_all(soft => {
    soft
    .expect(run("t=rows.ion", "t").stdout)
    .to_equal("$bag::[{a: 1}, {a: 2}]\n")
    soft.expect(run("t=list.ion", "t").stdout).to_equal("[1, 2]\n")
    soft.expect(run("t=one.ion", "t").stdout).to_equal("{a: 1}\n")
    soft.expect(run("t=empty.ion", "t").stdout).to_equal("$bag::[]\n")
    soft.expect(run("t=bag.ion", "t").stdout).to_equal("$bag::[1]\n")
    soft
    .expect(
      run("t=rows.ion", "SELECT VALUE r.a FROM t AS r WHERE r.a > 1").stdout,
    )
    .to_equal("$bag::[2]\n")
    // A MISSING global stays bound (plan ruling 1).
    soft.expect(run("t=missing.ion", "t").stdout).to_equal("$missing::null\n")
    soft.expect(run("t=missing.ion", "t IS MISSING").stdout).to_equal("true\n")
    // Review focus 5: boxed Ion prints back unchanged; a plain annotation is
    // not PartiQL-encoded Ion, so it is an error.
    soft.expect(run("t=boxed.ion", "t").stdout).to_equal("$ion::foo::1\n")
    soft
    .expect(run("t=annotated.ion", "t"))
    .to_equal(failed("partiql query: annotated.ion: unknown annotation foo\n"))
    // Review focus 4: the split is at the first '='.
    soft.expect(run("t=a=b.ion", "t").stdout).to_equal("7\n")
  })
}

///|
test "query binds --env structs and merges the bindings" {
  let io = query_io({
    "env.ion": "{t: [1, 2], u: 3}",
    "env2.ion": "{v: 4}",
    "clash.ion": "{t: 9}",
    "dup.ion": "{w: 1, w: 2}",
    "list.ion": "[1]",
    "two.ion": "{a: 1} {b: 2}",
    "n.ion": "5",
    "upper.ion": "6",
  })
  @expect.expect_all(soft => {
    soft
    .expect(
      query(
        [
          "--compact", "--env", "env.ion", "--env", "env2.ion", "--data", "n=n.ion",
          "-e", "[t, u, v, n]",
        ],
        io~,
      ).stdout,
    )
    .to_equal("[[1, 2], 3, 4, 5]\n")
    soft
    .expect(query(["--env", "env.ion", "--env", "clash.ion", "-e", "1"], io~))
    .to_equal(failed("partiql query: clash.ion: the global t is bound twice\n"))
    soft
    .expect(query(["--env", "env.ion", "--data", "t=n.ion", "-e", "1"], io~))
    .to_equal(failed("partiql query: n.ion: the global t is bound twice\n"))
    soft
    .expect(query(["--env", "dup.ion", "-e", "1"], io~))
    .to_equal(failed("partiql query: dup.ion: the global w is bound twice\n"))
    soft
    .expect(query(["--env", "list.ion", "-e", "1"], io~))
    .to_equal(failed("partiql query: list.ion: --env needs one Ion struct\n"))
    soft
    .expect(query(["--env", "two.ion", "-e", "1"], io~))
    .to_equal(failed("partiql query: two.ion: --env needs one Ion struct\n"))
    // Review focus 1: names that differ only in case are both bound; an
    // unquoted name finds the first.
    soft
    .expect(
      query(
        ["--compact", "--data", "T=upper.ion", "--data", "t=n.ion", "-e", "t"],
        io~,
      ).stdout,
    )
    .to_equal("6\n")
  })
}

///|
test "query reports unreadable and malformed binding files" {
  let io = query_io({ "bad.ion": "{a:", "date.ion": "$date::\"x\"" })
  @expect.expect_all(soft => {
    soft
    .expect(query(["--data", "t=nope.ion", "-e", "1"], io~))
    .to_equal(failed("partiql query: nope.ion: no such file: nope.ion\n"))
    soft
    .expect(query(["--data", "t=bad.ion", "-e", "1"], io~))
    .to_equal(
      failed(
        "partiql query: bad.ion: expected an Ion value, found end of input\n",
      ),
    )
    soft
    .expect(query(["--env", "date.ion", "-e", "1"], io~))
    .to_equal(
      failed("partiql query: date.ion: $date must be a struct, not String\n"),
    )
    soft
    .expect(query(["--data", "t=-", "-e", "1"], io=query_io({}, stdin="{a:")))
    .to_equal(
      failed(
        "partiql query: <stdin>: expected an Ion value, found end of input\n",
      ),
    )
  })
}

///|
test "query reads one binding or the statements from stdin" {
  @expect.expect_all(soft => {
    soft
    .expect(
      query(
        ["--compact", "--data", "t=-", "-e", "t"],
        io=query_io({}, stdin="[1]"),
      ).stdout,
    )
    .to_equal("[1]\n")
    soft
    .expect(
      query(
        ["--compact", "--env", "-", "q.sql"],
        io=query_io({ "q.sql": "t" }, stdin="{t: 1}"),
      ).stdout,
    )
    .to_equal("1\n")
    soft.expect(@cli.reads_stdin(["query"])).to_be_true()
    soft.expect(@cli.reads_stdin(["query", "-"])).to_be_true()
    soft
    .expect(@cli.reads_stdin(["query", "--env", "-", "-e", "1"]))
    .to_be_true()
    soft
    .expect(@cli.reads_stdin(["query", "--data", "t=-", "q.sql"]))
    .to_be_true()
    soft.expect(@cli.reads_stdin(["query", "-e", "1"])).to_be_false()
    soft.expect(@cli.reads_stdin(["query", "q.sql"])).to_be_false()
    soft
    .expect(@cli.reads_stdin(["query", "--data", "t=a.ion", "-e", "1"]))
    .to_be_false()
    // A run that ends in a usage error reads no stdin, so it never waits.
    for
      args in [
        ["query", "--env", "-", "--data", "t=-", "-e", "1"],
        ["query", "--data", "t=-"],
        ["query", "--data", "t"],
        ["query", "--data", "t=-", "--data", "t=a.ion", "-e", "1"],
      ] {
      soft.expect(@cli.reads_stdin(args), label=args.join(" ")).to_be_false()
    }
  })
}

///|
test "query usage errors" {
  @expect.expect_all(soft => {
    for
      args in [
        ["--data", "t", "-e", "1"],
        ["--data", "=f.ion", "-e", "1"],
        ["--data", "t=", "-e", "1"],
        ["--data", "t=a.ion", "--data", "t=b.ion", "-e", "1"],
        ["--data", "t=-"],
        ["--env", "-", "--data", "t=-", "-e", "1"],
        ["--env", "-", "--env", "-", "-e", "1"],
        ["--env", "-", "-"],
      ] {
      let outcome = query(args)
      soft.expect(outcome.status, label=args.join(" ")).to_equal(2)
      soft.expect(outcome.stdout, label=args.join(" ")).to_equal("")
      soft
      .expect(outcome.stderr, label=args.join(" "))
      .to_contain("Run 'partiql help query' for more information.")
    }
    soft
    .expect(query(["--data", "t", "-e", "1"]).stderr)
    .to_contain("--data needs NAME=FILE, found 't'")
    soft
    .expect(query(["--data", "t=a.ion", "--data", "t=b.ion", "-e", "1"]).stderr)
    .to_contain("--data binds t twice")
    soft
    .expect(query(["--data", "t=-"]).stderr)
    .to_contain("only one input can read stdin")
  })
}

///|
test "query reads the injected clock once per statement" {
  let calls = Ref(0)
  let clock : @eval.Clock = {
    now: () => {
      calls.val += 1
      @time.date_time(2026, 10, 16, hour=12)
    },
  }
  let io = query_io({}, clock=Some(clock))
  @expect.expect_all(soft => {
    let out = query(
      ["--compact", "-e", "CURRENT_DATE = DATE '2026-10-16'"],
      io~,
    )
    soft.expect(out.stdout).to_equal("true\n")
    soft.expect(calls.val).to_equal(1)
    ignore(query(["--compact", "-e", "CURRENT_DATE; 1; UTCNOW()"], io~))
    soft.expect(calls.val).to_equal(3)
    ignore(query(["--compact", "-e", "1 + 1"], io~))
    soft.expect(calls.val).to_equal(3)
  })
}

///|
test "query without a clock reports the clock function" {
  let out = query(["-e", "CURRENT_DATE"])
  @expect.expect_all(soft => {
    soft.expect(out.status).to_equal(1)
    soft.expect(out.stderr.contains("needs a clock")).to_be_true()
  })
}

///|
test "query help says the session time zone is UTC" {
  // CURRENT_DATE and the other clock functions read the session zone; the
  // CLI has no option for it yet (bead partiql-x69).
  let help = @cli.run(["help", "query"])
  @expect.expect(help.stdout).to_contain("The session time zone is UTC")
}

///|
test "query reports an unknown function at its name" {
  let out = query(["-e", "SELECT VALUE foo(x) FROM <<1>> AS x"])
  @expect.expect_all(soft => {
    soft.expect(out.status).to_equal(1)
    soft.expect(out.stdout).to_equal("")
    soft.expect(out.stderr).to_contain("unknown function foo")
  })
}
