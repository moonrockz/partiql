///|
test "= on collections compares elements as top-level = does" {
  let date = "DATE '2020-01-01'"
  let ts = "TIMESTAMP '2020-01-01 00:00:00'"
  let time = "TIME '12:00:00'"
  let time_tz = "TIME WITH TIME ZONE '12:00:00+00:00'"
  @expect.expect_all(soft => {
    soft.expect(ev("\{date} = \{ts}")).to_equal(Bool(true))
    soft.expect(ev("[\{date}] = [\{ts}]")).to_equal(Bool(true))
    soft.expect(ev("<<\{date}>> = <<\{ts}>>")).to_equal(Bool(true))
    soft.expect(ev("{'a': \{date}} = {'a': \{ts}}")).to_equal(Bool(true))
    soft.expect(ev("[[\{date}]] = [[\{ts}]]")).to_equal(Bool(true))
    soft.expect(ev("\{time} = \{time_tz}")).to_equal(Bool(true))
    soft.expect(ev("[\{time}] = [\{time_tz}]")).to_equal(Bool(true))
    soft
    .expect(ev("[\{date}] = [TIMESTAMP '2020-01-01 00:00:01']"))
    .to_equal(Bool(false))
    soft.expect(ev("[1, 2e0] = [1.0, 2]")).to_equal(Bool(true))
    soft.expect(ev("<<1, 2>> = <<2, 1.0>>")).to_equal(Bool(true))
  })
}

///|
test "IN uses =" {
  let date = "DATE '2020-01-01'"
  let ts = "TIMESTAMP '2020-01-01 00:00:00'"
  @expect.expect_all(soft => {
    soft.expect(ev("\{date} IN [\{ts}]")).to_equal(Bool(true))
    soft.expect(ev("\{date} IN <<1, \{ts}>>")).to_equal(Bool(true))
    soft.expect(ev("\{date} NOT IN [\{ts}]")).to_equal(Bool(false))
    soft
    .expect(ev("TIME '12:00:00' IN [TIME WITH TIME ZONE '12:00:00+00:00']"))
    .to_equal(Bool(true))
    soft.expect(ev("`2020-01-01T00:00:00Z` IN [\{ts}]")).to_equal(Bool(true))
    soft.expect(ev("[\{date}] IN [[\{ts}]]")).to_equal(Bool(true))
    soft.expect(ev("1 IN [NULL]")).to_equal(Null)
    soft.expect(ev("1 IN [MISSING]")).to_equal(Null)
  })
}

///|
test "NULL and MISSING: NULL wins at the top level, nested they are equal" {
  @expect.expect_all(soft => {
    soft.expect(ev("NULL = MISSING")).to_equal(Null)
    soft.expect(ev("MISSING = MISSING")).to_equal(Missing)
    soft.expect(ev("[NULL] = [NULL]")).to_equal(Bool(true))
    soft.expect(ev("[MISSING] = [MISSING]")).to_equal(Bool(true))
    // partiql-tests nary-operators.ion, equalListDifferentTypesWithNullMissingEquivalenceTrue
    soft.expect(ev("[1, 2e0, NULL] = [1.0, 2, MISSING]")).to_equal(Bool(true))
    soft.expect(ev("<<NULL>> = <<MISSING>>")).to_equal(Bool(true))
    soft.expect(ev("[NULL, MISSING] = [NULL]")).to_equal(Bool(false))
    soft.expect(ev("[NULL] = [1]")).to_equal(Bool(false))
  })
}
