///|
test "YAML query values preserve exact scalar types" {
  let actual = @yaml.read_text(
    "name: Ada\ncount: 9007199254740993\nprice: 1.2300\nitems: [true, null, yes]",
  )
  let expected = @ion.read_text(
    "{name: \"Ada\", count: 9007199254740993, price: 1.2300, items: [true, null, \"yes\"]}",
  )
  @expect.expect(actual).to_equal(expected)
}

///|
test "YAML core resolution rejects extensions and preserves decimal scale" {
  @expect.expect_all(soft => {
    for
      (source, expected) in [
        ("[012, 0o12, 0x12]", "[12, 10, 18]"),
        ("[.5, 1., 1e2, -0.00]", "[0.5, 1., 1d2, -0.00]"),
        (
          "[yes, OFF, 0b10, 1_000, 1:20, 2026-10-19]", "[\"yes\", \"OFF\", \"0b10\", \"1_000\", \"1:20\", \"2026-10-19\"]",
        ),
        ("text: |\n  hello\n  world\n", "{text: \"hello\\nworld\\n\"}"),
        ("text: >-\n  hello\n  world\n", "{text: \"hello world\"}"),
        (
          "[9223372036854775808, -9223372036854775809]", "[9223372036854775808, -9223372036854775809]",
        ),
        ("\u{feff}name: Ada\r\n", "{name: \"Ada\"}"),
      ] {
      soft
      .expect(@yaml.read_text(source) catch { e => fail(e.message()) })
      .to_equal(@ion.read_text(expected))
    }
    for
      source in [
        "{x: 1, x: 2}", "{true: 1}", "{[x]: 1}", "[1, 2", "%YAML 1.1\n---\nx", "%YAML 1.3\n---\nx",
        "x: \"\\uD800\"", "x: \u{0001}",
      ] {
      soft
      .expect_call(() => @yaml.read_text(source))
      .to_raise_matching(
        e => e is @yaml.YamlError::YamlError(..),
        description=source,
      )
    }
  })
}

///|
test "YAML bounds container nesting before building deep trees" {
  let source = "[".repeat(257) + "0" + "]".repeat(257)
  @expect.expect_call(() => @yaml.read_text(source)).to_raise_matching(
    e => e is @yaml.YamlError::YamlError(kind=Limit, ..),
    description="depth limit",
  )
}

///|
test "YAML explicit core tags preserve kind and exact spelling" {
  @expect.expect_all(soft => {
    for
      (source, expected) in [
        (
          "[!!str 123, !!str true, !!int '42', !!bool 'true', !!null '', !!float '1', !!float '-0']",
          "[\"123\", \"true\", 42, true, null, 1d0, -0d0]",
        ),
        (
          "!!map { !!str true: !!seq [! 123, !<tag:yaml.org,2002:float> '1.2300'] }",
          "{\"true\": [\"123\", 1.2300]}",
        ),
        (
          "%TAG !a! tag:yaml.org,2002:\n%TAG !b! tag:yaml.org,2002:\n---\n[!a!int '2', !b!str 3]",
          "[2, \"3\"]",
        ),
        ("! [1, 2]", "[1, 2]"),
      ] {
      soft
      .expect(@yaml.read_text(source) catch { e => fail(e.message()) })
      .to_equal(@ion.read_text(expected))
    }
    for
      source in [
        "!!int no", "!!int '1.2'", "!!bool yes", "!!str []", "!!seq text", "!!map []",
        "!custom 1", "!!timestamp 2026-10-19", "!!binary YQ==", "!!set {}", "!!omap []",
        "!!pairs []", "!!merge '<<'", "%TAG !a! tag:yaml.org,2002:\n%TAG !a! tag:yaml.org,2002:\n---\nx",
      ] {
      soft
      .expect_call(() => @yaml.read_text(source))
      .to_raise_matching(
        e => e is @yaml.YamlError::YamlError(..),
        description=source,
      )
    }
  })
}

///|
test "YAML streams preserve document boundaries and reset directives" {
  @expect.expect_all(soft => {
    for
      (source, expected) in [
        ("", ""),
        ("  # comment\n", ""),
        ("---\n...\n---\n", "null null"),
        ("--- [1, 2]\n...\n--- [3]\n", "[1, 2] [3]"),
        (
          "%TAG !x! tag:yaml.org,2002:\n--- !x!str true\n--- true", "\"true\" true",
        ),
        ("--- a\n...\n\u{feff}--- b\n", "\"a\" \"b\""),
      ] {
      soft
      .expect(@yaml.read_text(source) catch { e => fail(e.message()) })
      .to_equal(@ion.read_text(expected))
    }
    for
      source in [
        "--- 1\n--- [", "%TAG !x! tag:yaml.org,2002:\n--- !x!str true\n--- !x!str true",
      ] {
      soft
      .expect_call(() => @yaml.read_text(source))
      .to_raise_matching(
        e => {
          e
          is @yaml.YamlError::YamlError(location=Some({ document: 2, .. }), ..)
        },
        description="later document fails atomically",
      )
    }
  })
}

///|
test "YAML aliases copy values and reset anchors between documents" {
  @expect.expect_all(soft => {
    for
      (source, expected) in [
        ("[&a {x: [1]}, *a, &a 2, *a]", "[{x: [1]}, {x: [1]}, 2, 2]"),
        ("[&s hello, {*s : world}]", "[\"hello\", {hello: \"world\"}]"),
        ("[&a 1, &b [*a, *a], *b]", "[1, [1, 1], [1, 1]]"),
        ("[&a [], &b [*a], *b]", "[[], [[]], [[]]]"),
      ] {
      soft
      .expect(@yaml.read_text(source) catch { e => fail(e.message()) })
      .to_equal(@ion.read_text(expected))
    }
    for
      source in [
        "*missing", "[*later, &later 1]", "&self [*self]", "&a [&b [*a]]", "--- &a 1\n--- *a",
        "{ &a x: 1, *a : 2 }", "[&n 1, {*n : value}]",
      ] {
      soft
      .expect_call(() => @yaml.read_text(source))
      .to_raise_matching(
        e => e is @yaml.YamlError::YamlError(..),
        description=source,
      )
    }
  })
}

///|
test "mutating an alias occurrence leaves the anchor and other copies intact" {
  let values = @yaml.read_text("[&a {x: [1]}, *a, *a]")
  guard values is [List(items)] else { fail("expected list") }
  guard items[1] is Tuple(t) else { fail("expected tuple") }
  guard t.get_all("x") is [List(list)] else { fail("expected nested list") }
  list[0] = @value.Value::from_int(9)
  @expect.expect(values).to_equal(@ion.read_text("[{x:[1]}, {x:[9]}, {x:[1]}]"))
}

///|
test "YAML errors use view-relative Unicode coordinates and document numbers" {
  @expect.expect_all(soft => {
    let backing = "prefix{😀: 1, 😀: 2}suffix"
    soft
    .expect_call(() => @yaml.read_text(backing[6:20]))
    .to_raise_matching(
      e => {
        e
        is @yaml.YamlError::YamlError(
          kind=DuplicateKey,
          location=Some({ document: 1, line: 1, column: 8, }),
          ..
        )
      },
      description="Unicode columns in a nonzero view",
    )
    soft
    .expect_call(() => @yaml.read_text("--- ok\n--- bad\u{0001}"))
    .to_raise_matching(
      e => {
        e
        is @yaml.YamlError::YamlError(
          kind=Syntax,
          location=Some({ document: 2, line: 2, column: 8, }),
          ..
        )
      },
      description="invalid character in final document",
    )
    for
      bytes in [b"\xff", b"\xff\xfe\x61\x00", b"\x00\x00\xfe\xff", b"\x61\x00"] {
      soft
      .expect_call(() => @yaml.read_bytes(bytes))
      .to_raise_matching(
        e => e is @yaml.YamlError::YamlError(kind=Encoding, ..),
        description="strict UTF-8 input",
      )
    }
  })
}

///|
test "generated YAML numbers retain coefficient exponent and container values" {
  @quickcheck.check(
    (n : Int64) => {
      let spelling = n.to_string()
      let source = "{integer: " +
        spelling +
        ", decimal: " +
        spelling +
        "e-3, nested: [\"yes\", false]}"
      guard @yaml.read_text(source) is [Tuple(t)] else { return false }
      guard t.get_all("integer") is [Int(actual)] else { return false }
      guard t.get_all("decimal") is [Decimal(d)] else { return false }
      actual == n &&
      d.coefficient().to_string() == spelling &&
      d.exponent() == -3 &&
      t.get_all("nested") ==
      [
        @value.Value::from_list([
          @value.Value::from_string("yes"),
          @value.Value::from_bool(false),
        ]),
      ]
    },
    count=300,
  )
}

///|
test "YAML exact decimal sign and exponent boundaries" {
  @expect.expect_all(soft => {
    for
      (source, coefficient, exponent, negative_zero) in [
        ("-0.00", "0", -2, true),
        ("!!float '-0'", "0", 0, true),
        ("1.2300", "12300", -4, false),
        ("1e2147483647", "1", 2147483647, false),
        ("1e-2147483648", "1", -2147483648, false),
        ("+1.", "1", 0, false),
      ] {
      guard @yaml.read_text(source) is [Decimal(d)] else {
        fail("expected decimal: " + source)
      }
      soft.expect(d.coefficient().to_string()).to_equal(coefficient)
      soft.expect(d.exponent()).to_equal(exponent)
      soft.expect(d.is_negative_zero()).to_equal(negative_zero)
    }
    for source in ["1e2147483648", "1.0e-2147483648", "1e99999999999999"] {
      soft
      .expect_call(() => @yaml.read_text(source))
      .to_raise_matching(
        e => e is @yaml.YamlError::YamlError(kind=Limit, ..),
        description="decimal exponent budget",
      )
    }
    soft
    .expect(@yaml.read_text("[".repeat(256) + "0" + "]".repeat(256)).length())
    .to_equal(1)
    let anchor = "&a " + "[".repeat(255) + "0" + "]".repeat(255)
    soft
    .expect_call(() => @yaml.read_text("[" + anchor + ", [*a]]"))
    .to_raise_matching(
      e => e is @yaml.YamlError::YamlError(kind=Limit, ..),
      description="alias depth preflight",
    )
  })
}

///|
test "YAML arbitrary short source strings either decode or return typed errors" {
  @quickcheck.check(
    (source : String) => {
      try @yaml.read_text(source) catch {
        @yaml.YamlError::YamlError(..) => true
      } noraise {
        _ => true
      }
    },
    count=1000,
  )
}

///|
test "YAML empty block nodes and escaped tag URIs decode without losing values" {
  @expect.expect_all(soft => {
    for
      (source, expected) in [
        ("a:\n-\n- x\nb: y", "{a: [null, \"x\"], b: \"y\"}"),
        ("[!<tag:yaml.org,2002:%73tr> true]", "[\"true\"]"),
        ("a:\nb:\n  -\n  - c", "{a: null, b: [null, \"c\"]}"),
      ] {
      soft
      .expect(@yaml.read_text(source) catch { e => fail(e.message()) })
      .to_equal(@ion.read_text(expected))
    }
  })
}

///|
test "YAML duplicate checks use decoded keys including aliases and escapes" {
  @expect.expect_all(soft => {
    for source in ["{x: 1, \"\\u0078\": 2}", "{ &key x: 1, *key : 2 }"] {
      soft
      .expect_call(() => @yaml.read_text(source))
      .to_raise_matching(
        e => e is @yaml.YamlError::YamlError(kind=DuplicateKey, ..),
        description="decoded duplicate key",
      )
    }
    soft
    .expect_call(() => @yaml.read_text("[&n 1, {*n : value}]"))
    .to_raise_matching(
      e => e is @yaml.YamlError::YamlError(kind=Unsupported, ..),
      description="non-string alias key",
    )
    soft
    .expect(@yaml.read_text("{é: 1, é: 2}"))
    .to_equal(@ion.read_text("{\"é\": 1, \"é\": 2}"))
  })
}
