///|
/// Operands of every kind, also absent ones and Ion-boxed ones.
let cast_operands : Array[String] = [
  "0", "1", "-1", "127", "128", "2147483648", "9223372036854775807", "1.5", "-2.5",
  "0.125", "99.95", "1e3", "`1.5e0`", "`-0e0`", "`nan`", "`+inf`", "TRUE", "FALSE",
  "'12'", "' 1.5 '", "'abc'", "' true '", "'0x1F'", "'2020-01-01'", "'12:00:00'",
  "'2020-01-01 12:00:00'", "'1-2'", "''", "'😀'", "DATE '2020-02-29'", "TIME '23:59:59.9999'",
  "TIME WITH TIME ZONE '12:00:00+05:30'", "TIMESTAMP '2020-01-01 12:00:00.5'", "TIMESTAMP WITH TIME ZONE '2020-01-01 01:00:00+02:00'",
  "INTERVAL '1-2' YEAR TO MONTH", "INTERVAL '3 04:05:06.5' DAY TO SECOND", "INTERVAL '25' HOUR",
  "[1, 2]", "<<1>>", "{'a': 1}", "{'a': '1'}", "MAP {'a': 1}", "`{{\"abc\"}}`", "`abc`",
  "NULL", "MISSING", "`null.int`",
]

///|
/// Targets whose `IS` test is exact, so that the typing law can use it.
let cast_targets : Array[String] = [
  "BOOL", "TINYINT", "SMALLINT", "INT", "BIGINT", "DECIMAL", "DECIMAL(5, 2)", "NUMERIC(3)",
  "REAL", "DOUBLE PRECISION", "CHAR(3)", "VARCHAR(4)", "STRING", "CLOB", "BLOB",
  "DATE", "TIME", "TIME(1)", "TIME WITH TIME ZONE", "TIMESTAMP", "TIMESTAMP(0) WITH TIME ZONE",
  "INTERVAL YEAR TO MONTH", "INTERVAL DAY TO SECOND", "INTERVAL HOUR", "LIST", "BAG",
  "TUPLE", "MAP<STRING, INT>",
]

///|
/// The strict value of `source`, or `None` when it raises.
fn strict_value(source : String) -> @value.Value? {
  try ev(source, mode=Strict) catch {
    _ => None
  } noraise {
    v => Some(v)
  }
}

///|
test "law: a successful CAST(x AS T) IS T" {
  @expect.expect_all(soft => {
    for x in cast_operands {
      for t in cast_targets {
        let source = "CAST(\{x} AS \{t})"
        guard strict_value(source) is Some(v) else { continue }
        if v is (Null | Missing) {
          continue
        }
        soft
        .expect((source, strict_value("\{source} IS \{t}")))
        .to_equal((source, Some(Bool(true))))
      }
    }
  })
}

///|
test "law: CAST is idempotent" {
  @expect.expect_all(soft => {
    for x in cast_operands {
      for t in cast_targets {
        let once = "CAST(\{x} AS \{t})"
        guard strict_value(once) is Some(v) else { continue }
        let twice = strict_value("CAST(\{once} AS \{t})")
        soft
        .expect((once, twice is Some(w) && @value.eqg(v, w)))
        .to_equal((once, true))
      }
    }
  })
}

///|
test "law: NULL and MISSING pass through every target in both modes" {
  @expect.expect_all(soft => {
    for t in cast_targets {
      for mode in [@eval.Mode::Permissive, Strict] {
        soft.expect(ev("CAST(NULL AS \{t})", mode~)).to_equal(Null)
        soft.expect(ev("CAST(MISSING AS \{t})", mode~)).to_equal(Missing)
      }
    }
  })
}

///|
/// How a statement ends, for the modes law.
fn cast_outcome(source : String, mode : @eval.Mode) -> String {
  try ev(source, mode~) catch {
    TypeError(..) => "type error"
    DataError(..) => "data error"
    Unsupported(..) => "unsupported"
    Syntax(_) => "syntax"
  } noraise {
    v => @debug.to_string(v)
  }
}

///|
test "law: permissive MISSING exactly where strict raises a type error" {
  @expect.expect_all(soft => {
    for x in cast_operands {
      for t in cast_targets {
        let source = "CAST(\{x} AS \{t})"
        let strict = cast_outcome(source, Strict)
        let permissive = cast_outcome(source, Permissive)
        let expected = if strict == "type error" {
          @debug.to_string(@value.Value::Missing)
        } else {
          strict
        }
        soft.expect((source, permissive)).to_equal((source, expected))
      }
    }
  })
}

///|
/// A number literal and the type that keeps it.
fn number_and_type(text : String) -> (String, String) {
  if text.contains("e0`") {
    (text, "DOUBLE PRECISION")
  } else if text.contains(".") {
    (text, "DECIMAL")
  } else {
    (text, "BIGINT")
  }
}

///|
test "law: CAST through STRING and back gives the value" {
  let pairs : Array[(String, String)] = [
    ("TRUE", "BOOL"),
    ("`-2.5e-3`", "DOUBLE PRECISION"),
    ("`1e300`", "DOUBLE PRECISION"),
    ("`nan`", "DOUBLE PRECISION"),
    ("`-inf`", "DOUBLE PRECISION"),
    ("DATE '2020-02-29'", "DATE"),
    ("TIME '23:59:59.9999'", "TIME"),
    ("TIME WITH TIME ZONE '12:00:00.5+05:30'", "TIME WITH TIME ZONE"),
    ("TIMESTAMP '2020-01-01 12:00:00.5'", "TIMESTAMP"),
    (
      "TIMESTAMP WITH TIME ZONE '2020-01-01 01:00:00-08:00'", "TIMESTAMP WITH TIME ZONE",
    ),
    ("INTERVAL '1-2' YEAR TO MONTH", "INTERVAL YEAR TO MONTH"),
    ("INTERVAL '-3 04:05:06.5' DAY TO SECOND", "INTERVAL DAY TO SECOND"),
    ("INTERVAL '5' SECOND", "INTERVAL SECOND"),
    ("INTERVAL '1.5' SECOND", "INTERVAL SECOND"),
    ("INTERVAL '13' MONTH", "INTERVAL MONTH"),
    ("INTERVAL '25' HOUR", "INTERVAL HOUR"),
    ("INTERVAL '-90' MINUTE", "INTERVAL MINUTE"),
    ("INTERVAL '2' YEAR", "INTERVAL YEAR"),
    ("TIME (0) '12:00:00'", "TIME"),
  ]
  let rs = @splitmix.RandomState(seed=11UL)
  for _ in 0..<200 {
    pairs.push(number_and_type(gen_num(rs)))
  }
  @expect.expect_all(soft => {
    for pair in pairs {
      let (x, t) = pair
      guard strict_value(x) is Some(v) else { continue }
      let back = strict_value("CAST(CAST(\{x} AS STRING) AS \{t})")
      soft.expect((x, back is Some(w) && @value.eqg(v, w))).to_equal((x, true))
    }
  })
}
