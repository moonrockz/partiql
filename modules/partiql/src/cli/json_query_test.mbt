///|
test "query reads JSON data and environments from files and stdin" {
  let io = query_io(
    { "rows.json": "[{\"a\":2},{\"a\":3}]", "env.json": "{\"n\":4}" },
    stdin="[{\"a\":2},{\"a\":3}]",
  )
  let flags = ["--input-format", "json", "--output-format", "json", "--compact"]
  @expect.expect_all(soft => {
    for path in ["rows.json", "-"] {
      let result = query(
        [
          ..flags,
          "--data",
          "t=" + path,
          "--env",
          "env.json",
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
      io=query_io({}, stdin="{\"n\":4}"),
    )
    soft.expect(env_stdin.status).to_equal(0)
    soft.expect(env_stdin.stdout).to_equal("5\n")
    let each = query(
      [..flags, "--data", "t=rows.json", "--each", "t", "-e", "t.a"],
      io~,
    )
    soft.expect(each.status).to_equal(0)
    soft.expect(each.stdout).to_equal("2\n3\n")
  })
}

///|
test "JSON options have help and reject misuse before reading stdin" {
  let help = @cli.run(["help", "query"]).stdout
  @expect.expect_all(soft => {
    for
      text in [
        "--input-format", "--output-format", "json", "rows.json", "one JSON document",
      ] {
      soft.expect(help).to_contain(text)
    }
    for
      args in [
        ["--input-format", "yaml"],
        ["--input-format", "binary"],
        ["--output-format", "yaml"],
        ["--input-format"],
        ["--input-format", "json", "--env-schema", "x"],
        ["--input-format", "json", "--data-schema", "t=x"],
        ["--input-format", "json", "--schema-type", "x"],
        ["--input-format", "json", "--schema-document"],
        ["--input-format", "json", "--env", "-"],
      ] {
      let result = query(args)
      soft.expect(result.status).to_equal(2)
      soft.expect(@cli.reads_stdin(["query", ..args])).to_be_false()
    }
  })
}

///|
test "JSON failures name the file or unsupported result and emit no partial document" {
  let flags = ["--input-format", "json", "--output-format", "json", "--compact"]
  @expect.expect_all(soft => {
    for source in ["{a:1}", "[1,]", "1 2", ""] {
      let result = query(
        [..flags, "--data", "t=bad.json", "-e", "t"],
        io=query_io({ "bad.json": source }),
      )
      soft.expect(result.status).to_equal(1)
      soft.expect(result.stdout).to_equal("")
      soft.expect(result.stderr).to_contain("bad.json: JSON at offset")
    }
    let env = query(
      [..flags, "--env", "-", "-e", "1"],
      io=query_io({}, stdin="[]"),
    )
    soft.expect(env.status).to_equal(1)
    soft.expect(env.stderr).to_contain("--env needs one JSON object")
    for
      statement in [
        "MISSING", "<<1,2>>", "[1, MISSING]", "`nan`", "DATE '2024-01-01'",
      ] {
      let result = query([..flags, "-e", statement])
      soft.expect(result.status).to_equal(1)
      soft.expect(result.stdout).to_equal("")
      soft.expect(result.stderr).to_contain("cannot represent as JSON")
    }
    let partial = query([..flags, "-e", "1; MISSING; 3"])
    soft.expect(partial.status).to_equal(1)
    soft.expect(partial.stdout).to_equal("1\n")
  })
}

///|
test "JSON byte input, each cardinality and independent output formats" {
  let flags = ["--input-format", "json", "--data", "t=-", "-e", "t"]
  let io = {
    ..query_io({}),
    read_stdin_bytes: Some(() => @utf8.encode("{\"n\":9223372036854775808}")),
    read_file_bytes: Some(_ => @utf8.encode("{\"n\":9223372036854775808}")),
  }
  @expect.expect_all(soft => {
    let ion = query([..flags, "--compact"], io~)
    soft.expect(ion.status).to_equal(0)
    soft.expect(ion.stdout).to_equal("{n: 9223372036854775808}\n")
    let binary = query([..flags, "--output-format", "binary"], io~)
    soft.expect(binary.status).to_equal(0)
    soft
    .expect(@partiql_ion.read_bytes(binary.stdout_bytes.unwrap()))
    .to_equal(@partiql_ion.read_text("{n:9223372036854775808}"))
    let env = query(["--input-format", "json", "--env", "x", "-e", "n"], io~)
    soft.expect(env.status).to_equal(0)
    soft.expect(env.stdout).to_equal("9223372036854775808\n")
    let data_file = query(
      ["--input-format", "json", "--data", "t=x", "-e", "t.n"],
      io~,
    )
    soft.expect(data_file.stdout).to_equal(env.stdout)
    for source in ["[]", "true", "{}"] {
      let each = query(
        ["--input-format", "json", "--data", "t=-", "--each", "t", "-e", "1"],
        io=query_io({}, stdin=source),
      )
      soft.expect(each.status).to_equal(0)
      soft.expect(each.stdout).to_equal(if source == "[]" { "" } else { "1\n" })
    }
    let invalid_utf8 = query(flags, io={
      ..io,
      read_stdin_bytes: Some(() => b"\xff"),
    })
    soft.expect(invalid_utf8.status).to_equal(1)
    soft
    .expect(invalid_utf8.stderr)
    .to_contain("<stdin>: JSON text is not valid UTF-8")
    let json = query(
      ["--output-format", "json", "--data", "t=x", "-e", "t"],
      io=query_io({ "x": "{a: [1, 2]}" }),
    )
    soft.expect(json.status).to_equal(0)
    soft.expect(json.stdout).to_equal("{\n  \"a\": [\n    1,\n    2\n  ]\n}\n")
  })
}
