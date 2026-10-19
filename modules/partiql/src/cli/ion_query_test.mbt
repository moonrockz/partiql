///|
test "query accepts binary data and stdin and emits a binary datagram" {
  let rows = @partiql_ion.read_text("{a: 3} {a: 1} {a: 2}")
  let bytes = @partiql_ion.write_bytes(rows)
  let io = {
    ..query_io({}),
    read_file_bytes: Some(_ => bytes),
    read_stdin_bytes: Some(() => bytes),
  }
  let result = query(
    [
      "--output-format", "binary", "--data", "t=-", "-e", "SELECT VALUE r.a FROM t AS r; 9",
    ],
    io~,
  )
  let output = result.stdout_bytes.unwrap()
  @expect.expect_all(soft => {
    soft.expect(result.status).to_equal(0)
    soft.expect(result.stderr).to_equal("")
    soft.expect(result.stdout).to_equal("")
    soft
    .expect(@partiql_ion.read_bytes(output))
    .to_equal(@partiql_ion.read_text("$bag::[3, 1, 2] 9"))
    soft
    .expect(query(["--compact", "--data", "t=rows.any", "-e", "t"], io~).stdout)
    .to_equal("$bag::[{a: 3}, {a: 1}, {a: 2}]\n")
  })
}

///|
test "query runs each datagram element and retains valid binary output on failure" {
  let io = query_io({
    "rows": "{a: 3} {a: 1} {a: 2}",
    "empty": "",
    "encoded": "$bag::[1] $missing::null 3",
  })
  @expect.expect_all(soft => {
    soft
    .expect(
      query(
        ["--compact", "--data", "t=rows", "--each", "t", "-e", "t.a; 9"],
        io~,
      ).stdout,
    )
    .to_equal("3\n9\n1\n9\n2\n9\n")
    soft
    .expect(
      query(
        ["--compact", "--data", "t=rows", "-e", "SELECT VALUE r.a FROM t AS r"],
        io~,
      ).stdout,
    )
    .to_equal("$bag::[3, 1, 2]\n")
    soft
    .expect(
      query(["--data", "t=empty", "--each", "t", "-e", "1 / 0"], io~).stdout,
    )
    .to_equal("")
    soft
    .expect(
      query(["--compact", "--data", "t=encoded", "--each", "t", "-e", "t"], io~).stdout,
    )
    .to_equal("$bag::[1]\n$missing::null\n3\n")
    let failed = query(["--output-format", "binary", "-e", "1; 1 / 0; 3"])
    soft.expect(failed.status).to_equal(1)
    soft.expect(failed.stderr).to_contain("division by zero")
    soft
    .expect(@partiql_ion.read_bytes(failed.stdout_bytes.unwrap()))
    .to_equal([@value.Value::from_int(1)])
  })
}

///|
test "query reports malformed binary input and validates byte environments" {
  let env = @partiql_ion.write_bytes(@partiql_ion.read_text("{a: 2}"))
  let io = { ..query_io({}), read_file_bytes: Some(_ => env), }
  let broken = {
    ..query_io({}),
    read_file_bytes: Some(_ => b"\xe0\x01\x00\xea\x21"),
  }
  @expect.expect_all(soft => {
    soft
    .expect(query(["--env", "environment", "-e", "a + 1"], io~).stdout)
    .to_equal("3\n")
    let outcome = query(["--data", "t=broken", "-e", "t"], io=broken)
    soft.expect(outcome.status).to_equal(1)
    soft.expect(outcome.stdout).to_equal("")
    soft.expect(outcome.stderr).to_contain("partiql query: broken: binary Ion:")
  })
}

///|
test "query validates all raw input before evaluation and reports every schema violation" {
  let io = query_io({
    "schema": "$ion_schema_2_0 type::{name: row, type: struct, fields: {a: {type: int, occurs: required}, b: {type: string, occurs: required}}}",
    "good": "{a: 1, b: \"ok\"}",
    "bad": "{a: false, b: 2} {a: \"no\", b: false}",
    "document-schema": "$ion_schema_2_0 type::{name: rows, type: document, element: int, container_length: 2}",
    "ints": "1 2",
  })
  let flags = ["--data-schema", "t=schema", "--schema-type", "row"]
  @expect.expect_all(soft => {
    soft
    .expect(query([..flags, "--data", "t=good", "-e", "t.a"], io~).stdout)
    .to_equal("1\n")
    let invalid = query([..flags, "--data", "t=bad", "-e", "1 / 0"], io~)
    soft.expect(invalid.status).to_equal(1)
    soft.expect(invalid.stdout).to_equal("")
    for path in ["$[0].a", "$[0].b", "$[1].a", "$[1].b"] {
      soft.expect(invalid.stderr).to_contain(path)
    }
    soft.expect(invalid.stderr.contains("division by zero")).to_be_false()
    soft
    .expect(
      query(
        [
          "--env", "good", "--env-schema", "schema", "--schema-type", "row", "-e",
          "a",
        ],
        io~,
      ).stdout,
    )
    .to_equal("1\n")
    soft
    .expect(
      query(
        [
          "--data", "t=ints", "--data-schema", "t=document-schema", "--schema-type",
          "rows", "--schema-document", "--compact", "-e", "t",
        ],
        io~,
      ).stdout,
    )
    .to_equal("$bag::[1, 2]\n")
    let binary = @partiql_ion.write_bytes(
      @partiql_ion.read_text("{a: false, b: 2} {a: \"no\", b: false}"),
    )
    let binary_io = {
      ..io,
      read_file_bytes: Some(path => {
        if path == "bad" {
          binary
        } else {
          @utf8.encode((io.read_file)(path))
        }
      }),
    }
    soft
    .expect(
      query([..flags, "--data", "t=bad", "-e", "1 / 0"], io=binary_io).stderr,
    )
    .to_equal(invalid.stderr)
  })
}

///|
test "Ion query options have help and reject invalid combinations without reading stdin" {
  @expect.expect_all(soft => {
    let help = @cli.run(["help", "query"]).stdout
    for
      option in [
        "--each", "--output-format", "--data-schema", "--env-schema", "--schema-type",
        "--schema-document",
      ] {
      soft.expect(help).to_contain(option)
    }
    for
      args in [
        ["--output-format", "bad"],
        ["--each", "absent"],
        ["--data-schema", "bad"],
        ["--data-schema", "x=schema"],
        ["--env-schema", "schema"],
        ["--schema-type", "row"],
        ["--schema-document"],
        ["--data", "t=-", "--data-schema", "t=-"],
        ["--data", "t=file", "--data-schema", "t=one", "--data-schema", "t=two"],
      ] {
      let full = ["query", ..args, "-e", "1"]
      soft.expect(@cli.run(full).status, label=args.join(" ")).to_equal(2)
      soft.expect(@cli.reads_stdin(full), label=args.join(" ")).to_be_false()
    }
  })
}
