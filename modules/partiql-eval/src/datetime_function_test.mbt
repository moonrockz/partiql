///|
test "EXTRACT evaluates" {
  @expect.expect_all(soft => {
    soft.expect(ev("EXTRACT(YEAR FROM DATE '2024-02-29')")).to_equal(Int(2024))
    soft
    .expect(
      ev(
        "EXTRACT(TIMEZONE_MINUTE FROM TIME WITH TIME ZONE '01:23:45.678-06:30')",
      ),
    )
    .to_equal(Int(-30))
    soft
    .expect(ev("EXTRACT(SECOND FROM TIME '01:23:45.678')"))
    .to_equal(dec("45.678"))
    soft.expect(ev("EXTRACT(HOUR FROM DATE '2024-02-29')")).to_equal(Missing)
    soft
    .expect(failure_of("EXTRACT(HOUR FROM DATE '2024-02-29')", mode=Strict))
    .to_equal("type")
    soft.expect(ev("EXTRACT(YEAR FROM NULL)")).to_equal(Null)
    soft.expect(ev("EXTRACT(YEAR FROM MISSING)")).to_equal(Missing)
  })
}

///|
test "datetime function calls: static checks" {
  @expect.expect_all(soft => {
    for
      source in [
        "DATE_ADD(TIMEZONE_HOUR, 1, TIMESTAMP '2020-01-01 00:00:00+00:00')", "DATE_DIFF(TIMEZONE_MINUTE, DATE '2020-01-01', DATE '2020-01-02')",
        "TO_STRING(DATE '2020-01-01')", "TO_STRING(DATE '2020-01-01', 'y', 'M')",
        "TO_TIMESTAMP()", "TO_TIMESTAMP('a', 'b', 'c')", "TO_STRING(DISTINCT DATE '2020-01-01', 'y')",
      ] {
      soft.expect((source, failure_of(source))).to_equal((source, "data"))
      soft
      .expect((source, failure_of(source, mode=Strict)))
      .to_equal((source, "data"))
    }
  })
}

///|
test "DATE_ADD evaluates" {
  @expect.expect_all(soft => {
    // An Ion literal evaluates to the boxed Ion value, so compare with `=`.
    soft
    .expect(ev("DATE_ADD(month, 1, `2010T`) = `2010-02T`"))
    .to_equal(Bool(true))
    soft
    .expect(ev("DATE_ADD(day, -1, DATE '2024-03-01')"))
    .to_equal(ev("DATE '2024-02-29'"))
    soft
    .expect(failure_of("DATE_ADD(month, 1, DATE '2025-01-31')", mode=Strict))
    .to_equal("data")
    soft.expect(ev("DATE_ADD(year, NULL, MISSING)")).to_equal(Missing)
  })
}

///|
test "DATE_DIFF evaluates" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev("DATE_DIFF(hour, DATE '2025-01-15', TIMESTAMP '2025-01-14 12:30:45')"),
    )
    .to_equal(Int(-11))
    soft
    .expect(
      ev("DATE_DIFF(day, `2017-01-02T01:00+10:00`, `2017-01-02T01:00+00:00`)"),
    )
    .to_equal(Int(0))
    soft
    .expect(
      ev(
        "DATE_DIFF(hour, TIME '08:15:45', TIME WITH TIME ZONE '08:15:45+02:00')",
      ),
    )
    .to_equal(Int(-2))
    soft
    .expect(
      failure_of(
        "DATE_DIFF(hour, TIME '08:15:45', DATE '2020-01-01')",
        mode=Strict,
      ),
    )
    .to_equal("type")
  })
}
