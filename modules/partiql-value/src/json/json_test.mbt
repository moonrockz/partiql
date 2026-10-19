///|
test "JSON rejects invalid syntax and Ion extensions with positions" {
  @expect.expect_all(soft => {
    for
      source in [
        "", " ", "1 2", "{}{}", "[1,]", "{\"a\":1,}", "{'a':1}", "{a:1}", "/* comment */1",
        "// comment\n1", "1_000", "01", "+1", ".5", "1.", "1e", "1e+", "NaN", "Infinity",
        "$bag::[1]", "foo::1", "null.int", "[1 2]", "{\"x\" 1}", "truex", "\u{feff}null",
        "\"\u{0001}\"", "\"\\uD800\"", "\"\\uDC00\"", "\"\\x20\"", "\"unfinished",
        "1e2147483648", "1.0e-2147483648",
      ] {
      soft
      .expect_call(() => @partiql_json.read_text(source))
      .to_raise_matching(
        e => e is @partiql_json.JsonError::Syntax(..),
        description=source,
      )
    }
    soft
    .expect_call(() => @partiql_json.read_bytes(b"\xff"))
    .to_raise_matching(
      e => e is @partiql_json.JsonError::Utf8,
      description="invalid UTF-8",
    )
  })
}

///|
test "JSON output is strict and preserves parsed values including decimal scale" {
  @expect.expect_all(soft => {
    for
      source in [
        "null", "true", "false", "0", "-0", "-9223372036854775809", "9223372036854775807",
        "1.2300", "-0.00", "1e2", "1e-2147483648", "1e2147483647", "1e400", "[]",
        "{}", "[1,2.0,[null]]", "{\"a\":1,\"a\":2}", "\"\\\"\\\\\\b\\f\\n\\r\\t/😀\"",
      ] {
      let value = @partiql_json.read_text(source)
      for pretty in [false, true] {
        let text = @partiql_json.write_text(value, pretty~)
        soft.expect(@core_json.valid(text)).to_be_true()
        soft.expect(@partiql_json.read_text(text)).to_equal(value)
      }
      soft
      .expect(@partiql_json.read_bytes(@partiql_json.write_bytes(value)))
      .to_equal(value)
    }
  })
}

///|
test "JSON rejects every unsupported PartiQL kind, including nested values" {
  let date = @value.Date::Date(year=2024, month=1, day=1)
  let time = @value.Time::Time(hour=0, minute=0, second=0)
  let unsupported : Array[@value.Value] = [
    Missing,
    @value.Value::from_bag(@value.Bag([])),
    @value.Value::from_map(
      @value.MapValue(key_type=String, value_type=Dynamic, []),
    ),
    @value.Value::from_graph(@value.GraphValue([], [])),
    @value.Value::from_date(date),
    @value.Value::from_time(time),
    @value.Value::from_timestamp(@value.Timestamp(date, time)),
    @value.Value::from_interval_ym(@value.IntervalYM(1L)),
    @value.Value::from_interval_dt(@value.IntervalDT(1L, 0L)),
    @value.Value::from_blob(b"x"),
    @value.Value::from_clob(b"x"),
    @partiql_ion.read_text("$ion::1")[0],
    @value.Value::from_float(@double.not_a_number),
    @value.Value::from_float(@double.infinity),
    @value.Value::from_float(@double.neg_infinity),
  ]
  @expect.expect_all(soft => {
    for value in unsupported {
      let cases = [value, @value.Value::from_list([value])]
      // Tuple's constructor intentionally removes MISSING fields.
      if value != Missing {
        cases.push(@value.Value::from_tuple(@value.Tuple([("x", value)])))
      }
      for nested in cases {
        soft
        .expect_call(() => @partiql_json.write_text(nested))
        .to_raise_matching(
          e => e is @partiql_json.JsonError::Unsupported(_),
          description="unsupported value",
        )
      }
    }
  })
}

///|
test "finite floats retain binary64 precision when consumed as binary64" {
  @expect.expect_all(soft => {
    for f in [0.0, -0.0, 0.1, 1.5, @double.max_value, @double.min_positive] {
      let text = @partiql_json.write_text(@value.Value::from_float(f))
      match @core_json.parse(text) {
        Number(actual, ..) =>
          soft
          .expect(actual.reinterpret_as_int64())
          .to_equal(f.reinterpret_as_int64())
        _ => fail("float output must be a JSON number")
      }
    }
  })
}

///|
test "JSON round trips generated nested objects with duplicate keys and exact numbers" {
  @quickcheck.check(
    (fields : Array[(String, Int64)]) => {
      let entries = fields.map(pair => {
        let key = Json::string(pair.0).stringify()
        let n = pair.1.to_string()
        key + ":[" + n + "," + n + "e-3,{" + key + ":true," + key + ":null}]"
      })
      let source = "{" + entries.join(",") + "}"
      let value = @partiql_json.read_text(source)
      let text = @partiql_json.write_text(value)
      @core_json.valid(text) && @partiql_json.read_text(text) == value
    },
    count=300,
  )
}

///|
test "JSON nesting limits fail with typed errors" {
  let accepted = "[".repeat(256) + "0" + "]".repeat(256)
  let too_deep = "[" + accepted + "]"
  let value = @partiql_json.read_text(accepted)
  @expect.expect_all(soft => {
    soft.expect(@partiql_json.write_text(value)).to_equal(accepted)
    soft
    .expect_call(() => @partiql_json.read_text(too_deep))
    .to_raise_matching(
      e => e is @partiql_json.JsonError::Syntax(..),
      description="read nesting limit",
    )
    soft
    .expect_call(() => {
      @partiql_json.write_text(@value.Value::from_list([value]))
    })
    .to_raise_matching(
      e => e is @partiql_json.JsonError::Unsupported(_),
      description="write nesting limit",
    )
  })
}

///|
test "JSON syntax offsets identify the malformed character in the full document" {
  @expect.expect_all(soft => {
    for
      (source, expected) in [
        ("[\n  \"prefix\\x20\"]", 12),
        ("[\"😀\\x20\"]", 5),
        ("{\"a\": 01}", 7),
        ("[1e+]", 4),
        ("[\"prefix\\uD800\"]", 8),
      ] {
      soft
      .expect_call(() => @partiql_json.read_text(source))
      .to_raise_matching(
        e => {
          match e {
            @partiql_json.JsonError::Syntax(offset~, ..) => offset == expected
            _ => false
          }
        },
        description="document-relative offset in " + source,
      )
    }
  })
}
