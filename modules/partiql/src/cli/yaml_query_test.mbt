///|
test "query reads YAML data and environments from files and stdin" {
  let io = query_io(
    { "rows.yaml": "- a: 2\n- a: 3", "env.yaml": "n: 4" },
    stdin="- a: 2\n- a: 3",
  )
  let flags = ["--input-format", "yaml", "--output-format", "json", "--compact"]
  @expect.expect_all(soft => {
    for path in ["rows.yaml", "-"] {
      let result = query(
        [
          ..flags,
          "--data",
          "t=" + path,
          "--env",
          "env.yaml",
          "-e",
          "CAST((SELECT VALUE r.a + n FROM t AS r) AS LIST)",
        ],
        io~,
      )
      soft.expect(result.status).to_equal(0)
      soft.expect(result.stderr).to_equal("")
      soft.expect(result.stdout).to_equal("[6,7]\n")
    }
    let env_stdin = query(
      [..flags, "--env", "-", "-e", "n + 1"],
      io=query_io({}, stdin="n: 4"),
    )
    soft.expect(env_stdin.status).to_equal(0)
    soft.expect(env_stdin.stdout).to_equal("5\n")
    let each = query(
      [..flags, "--data", "t=rows.yaml", "--each", "t", "-e", "t.a"],
      io~,
    )
    soft.expect(each.status).to_equal(0)
    soft.expect(each.stdout).to_equal("2\n3\n")
  })
}

///|
test "YAML stream cardinality and each preserve whole documents" {
  let flags = ["--input-format", "yaml", "--data", "t=-", "--compact"]
  @expect.expect_all(soft => {
    for
      (source, normal, each) in [
        ("", "$bag::[]\n", ""),
        ("# empty\n", "$bag::[]\n", ""),
        ("---\n", "null\n", "null\n"),
        ("[]", "[]\n", ""),
        ("[1, 2]", "[1, 2]\n", "1\n2\n"),
        ("--- [1, 2]\n--- [3]\n", "$bag::[[1, 2], [3]]\n", "[1, 2]\n[3]\n"),
        (
          "--- {a: 1}\n--- {a: 2}\n", "$bag::[{a: 1}, {a: 2}]\n", "{a: 1}\n{a: 2}\n",
        ),
      ] {
      let io = query_io({}, stdin=source)
      let result = query([..flags, "-e", "t"], io~)
      let iterated = query([..flags, "--each", "t", "-e", "t"], io~)
      soft.expect(result.status).to_equal(0)
      soft.expect(result.stdout).to_equal(normal)
      soft.expect(iterated.status).to_equal(0)
      soft.expect(iterated.stdout).to_equal(each)
    }
    let result = query(
      [..flags, "-e", "SELECT VALUE r.a FROM t AS r"],
      io=query_io({}, stdin="--- {a: 1}\n--- {a: 2}"),
    )
    soft.expect(result.status).to_equal(0)
    soft.expect(result.stdout).to_equal("$bag::[1, 2]\n")
  })
}

///|
test "YAML loading errors prevent evaluation and output" {
  let flags = [
    "--input-format", "yaml", "--data", "t=bad.yaml", "--each", "t", "-e", "1; 1 / 0",
  ]
  @expect.expect_all(soft => {
    for
      source in [
        "--- 1\n--- [", "--- 1\n--- !!bool yes", "[&a 1, *missing]", "{x: 1, x: 2}",
        "{true: 1}", "%YAML 1.1\n---\nx",
      ] {
      let result = query(flags, io=query_io({ "bad.yaml": source }))
      soft.expect(result.status).to_equal(1)
      soft.expect(result.stdout).to_equal("")
      soft.expect(result.stderr).to_contain("bad.yaml: YAML document")
    }
    for source in ["", "[]", "--- {n: 1}\n--- {n: 2}"] {
      let result = query(
        ["--input-format", "yaml", "--env", "-", "-e", "1"],
        io=query_io({}, stdin=source),
      )
      soft.expect(result.status).to_equal(1)
      soft.expect(result.stdout).to_equal("")
      soft.expect(result.stderr).to_contain("exactly one YAML mapping document")
    }
  })
}

///|
test "YAML options reject schemas before any input is read" {
  let reads = Ref(0)
  let io = {
    ..query_io({}),
    read_file: _ => {
      reads.val += 1
      ""
    },
    read_stdin: () => {
      reads.val += 1
      ""
    },
  }
  @expect.expect_all(soft => {
    for
      schema in [
        ["--env-schema", "s"],
        ["--data-schema", "t=s"],
        ["--schema-type", "s"],
        ["--schema-document"],
      ] {
      let args = [
        "query", "--input-format", "yaml", "--data", "t=-", "-e", "1", ..schema,
      ]
      soft.expect(@cli.run(args, io~).status).to_equal(2)
      soft.expect(@cli.reads_stdin(args)).to_be_false()
    }
    soft.expect(reads.val).to_equal(0)
    soft
    .expect(query(["--input-format", "unknown", "-e", "1"]).status)
    .to_equal(2)
    soft
    .expect(query(["--output-format", "yaml", "-e", "1"]).status)
    .to_equal(2)
  })
}

///|
test "YAML exact values work with Ion binary and JSON outputs" {
  let flags = [
    "--input-format", "yaml", "--data", "t=-", "-e", "t", "--compact",
  ]
  let io = {
    ..query_io({}),
    read_stdin_bytes: Some(() => {
      @utf8.encode("n: 9223372036854775808\nd: -0.00\nx: 1.2300")
    }),
  }
  @expect.expect_all(soft => {
    let ion = query(flags, io~)
    soft.expect(ion.status).to_equal(0)
    soft
    .expect(ion.stdout)
    .to_equal("{n: 9223372036854775808, d: -0.00, x: 1.2300}\n")
    let json = query([..flags, "--output-format", "json"], io~)
    soft.expect(json.status).to_equal(0)
    soft
    .expect(json.stdout)
    .to_equal("{\"n\":9223372036854775808,\"d\":-0e-2,\"x\":12300e-4}\n")
    let binary = query([..flags, "--output-format", "binary"], io~)
    soft.expect(binary.status).to_equal(0)
    soft
    .expect(@partiql_ion.read_bytes(binary.stdout_bytes.unwrap()))
    .to_equal(@partiql_ion.read_text(ion.stdout))
    for source in [".inf", "-.Inf", ".NaN"] {
      let result = query(
        [..flags, "--output-format", "json"],
        io=query_io({}, stdin=source),
      )
      soft.expect(result.status).to_equal(1)
      soft.expect(result.stdout).to_equal("")
      soft.expect(result.stderr).to_contain("cannot represent as JSON")
    }
  })
}

///|
test "YAML help documents input-only behavior and examples" {
  let help = @cli.run(["help", "query"]).stdout
  @expect.expect_all(soft => {
    for
      text in [
        "yaml", "rows.yaml", "Core 1.2", "input-only", "whole documents", "64 MiB",
        "Ion Schema",
      ] {
      soft.expect(help).to_contain(text)
    }
  })
}
