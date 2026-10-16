///|
/// Timestamps of every kind: with and without offsets, fractions, the year
/// limits and a leap day.
let law_timestamps : Array[String] = [
  "TIMESTAMP '2020-02-29 23:59:59.123456789+05:30'", "TIMESTAMP '0001-01-01 00:00:00'",
  "TIMESTAMP '9999-12-31 23:59:59.9+00:00'", "TIMESTAMP '2017-01-02 03:04:05.006-08:00'",
  "TIMESTAMP '1999-12-31 12:00:00'", "`2017T`", "`2017-06-15T10:20:30.5Z`",
]

///|
let law_fields : Array[String] = ["day", "hour", "minute", "second"]

///|
test "law: DATE_DIFF undoes DATE_ADD for day to second" {
  let rs = @splitmix.RandomState(seed=17UL)
  @expect.expect_all(soft => {
    for x in law_timestamps {
      for f in law_fields {
        let n = pick(rs, 2001) - 1000
        let added = "DATE_ADD(\{f}, \{n}, \{x})"
        guard strict_value(added) is Some(_) else { continue }
        let source = "DATE_DIFF(\{f}, \{x}, \{added})"
        soft
        .expect((source, strict_value(source)))
        .to_equal((source, Some(Int(n.to_int64()))))
      }
    }
  })
}

///|
test "law: DATE_DIFF undoes DATE_ADD for months when no month end overflows" {
  @expect.expect_all(soft => {
    for
      x in [
        "DATE '2020-01-15'", "TIMESTAMP '2019-07-28 10:00:00+01:00'", "`2017T`",
      ] {
      for n in [-25, -12, -1, 0, 1, 11, 12, 37] {
        for f in ["month", "year"] {
          let added = "DATE_ADD(\{f}, \{n}, \{x})"
          guard strict_value(added) is Some(_) else { continue }
          let source = "DATE_DIFF(\{f}, \{x}, \{added})"
          soft
          .expect((source, strict_value(source)))
          .to_equal((source, Some(Int(n.to_int64()))))
        }
      }
    }
  })
}

///|
test "law: TO_TIMESTAMP reads back TO_STRING with a complete pattern" {
  // The pattern `yyyy-MM-dd'T'HH:mm:ss.SSSSSSSSSXXX` as a PartiQL string
  // literal, where a quote is doubled.
  let pattern = "yyyy-MM-dd''T''HH:mm:ss.SSSSSSSSSXXX"
  @expect.expect_all(soft => {
    for x in law_timestamps {
      let with_zone = "CAST(\{x} AS TIMESTAMP WITH TIME ZONE)"
      guard strict_value(with_zone) is Some(v) else { continue }
      let source = "TO_TIMESTAMP(TO_STRING(\{with_zone}, '\{pattern}'), '\{pattern}')"
      guard strict_value(source) is Some(w) else {
        soft.expect((source, "fails")).to_equal((source, "ok"))
        continue
      }
      soft.expect((source, @value.eqg(v, w))).to_equal((source, true))
    }
  })
}

///|
test "law: OVERLAPS is symmetric" {
  let periods = [
    "[DATE '2023-01-01', DATE '2023-01-10']", "[DATE '2023-01-10', DATE '2023-01-01']",
    "[DATE '2023-01-05', INTERVAL '3' DAY]", "[NULL, DATE '2023-01-07']", "[DATE '2023-01-10', NULL]",
    "[TIMESTAMP '2023-01-10 00:00:00', TIMESTAMP '2023-01-20 00:00:00']", "<<DATE '2023-01-02', DATE '2023-01-03'>>",
  ]
  @expect.expect_all(soft => {
    for p in periods {
      for q in periods {
        soft
        .expect((p, q, strict_value("\{p} OVERLAPS \{q}")))
        .to_equal((p, q, strict_value("\{q} OVERLAPS \{p}")))
      }
    }
  })
}

///|
test "law: EXTRACT rebuilds a timestamp" {
  @expect.expect_all(soft => {
    for x in law_timestamps {
      guard strict_value(x) is Some(v) else { continue }
      let parts = ["YEAR", "MONTH", "DAY", "HOUR", "MINUTE"].map(f => {
        strict_value("EXTRACT(\{f} FROM \{x})")
      })
      guard v is Timestamp(ts) else { continue }
      let expected : Array[@value.Value?] = [
        Some(Int(ts.date.year.to_int64())),
        Some(Int(ts.date.month.to_int64())),
        Some(Int(ts.date.day.to_int64())),
        Some(Int(ts.time.hour.to_int64())),
        Some(Int(ts.time.minute.to_int64())),
      ]
      soft.expect((x, parts)).to_equal((x, expected))
    }
  })
}

///|
test "law: absent arguments give MISSING, then NULL, in both modes" {
  // `$x` marks the absent argument.
  let calls = [
    "EXTRACT(YEAR FROM $x)", "DATE_ADD(day, 1, $x)", "DATE_DIFF(day, $x, DATE '2020-01-01')",
    "TO_STRING($x, 'y')", "TO_TIMESTAMP($x)", "TO_TIMESTAMP($x, 'y')", "$x OVERLAPS [DATE '2020-01-01', DATE '2020-01-02']",
  ]
  @expect.expect_all(soft => {
    for call in calls {
      for mode in [@eval.Mode::Permissive, Strict] {
        soft
        .expect(ev(call.replace(old="$x", new="MISSING"), mode~))
        .to_equal(Missing)
        soft
        .expect(ev(call.replace(old="$x", new="NULL"), mode~))
        .to_equal(Null)
      }
    }
  })
}
