///|
test "IS CHAR(n) and IS VARCHAR(n) check the length in characters" {
  @expect.expect_all(soft => {
    soft.expect(ev("'abcd' IS VARCHAR(3)")).to_equal(Bool(false))
    soft.expect(ev("'abc' IS VARCHAR(3)")).to_equal(Bool(true))
    soft.expect(ev("'' IS VARCHAR(3)")).to_equal(Bool(true))
    soft.expect(ev("'abcd' IS NOT VARCHAR(3)")).to_equal(Bool(true))
    soft.expect(ev("'abc' IS CHAR(3)")).to_equal(Bool(true))
    soft.expect(ev("'ab' IS CHAR(3)")).to_equal(Bool(false))
    soft.expect(ev("'abcd' IS CHAR(3)")).to_equal(Bool(false))
    // code points, not UTF-16 units
    soft.expect(ev("'😀😀' IS VARCHAR(2)")).to_equal(Bool(true))
    soft.expect(ev("'😀😀' IS CHAR(2)")).to_equal(Bool(true))
    soft.expect(ev("1 IS VARCHAR(3)")).to_equal(Bool(false))
    soft.expect(ev("'abcd' IS VARCHAR")).to_equal(Bool(true))
  })
}

///|
test "IS TIME(p) and IS TIMESTAMP(p) check the fraction digits" {
  @expect.expect_all(soft => {
    soft.expect(ev("TIME '12:00:00.123' IS TIME(0)")).to_equal(Bool(false))
    soft.expect(ev("TIME '12:00:00.123' IS TIME(2)")).to_equal(Bool(false))
    soft.expect(ev("TIME '12:00:00.123' IS TIME(3)")).to_equal(Bool(true))
    soft.expect(ev("TIME '12:00:00' IS TIME(0)")).to_equal(Bool(true))
    soft.expect(ev("TIME '12:00:00.120' IS TIME(2)")).to_equal(Bool(true))
    soft.expect(ev("TIME '12:00:00.123' IS TIME")).to_equal(Bool(true))
    soft
    .expect(
      ev("TIME WITH TIME ZONE '12:00:00.5+01:00' IS TIME(0) WITH TIME ZONE"),
    )
    .to_equal(Bool(false))
    soft
    .expect(ev("TIMESTAMP '2020-01-01 12:00:00.123' IS TIMESTAMP(0)"))
    .to_equal(Bool(false))
    soft
    .expect(ev("TIMESTAMP '2020-01-01 12:00:00.123' IS TIMESTAMP(6)"))
    .to_equal(Bool(true))
    soft
    .expect(ev("TIMESTAMP '2020-01-01 12:00:00' IS TIMESTAMP(0)"))
    .to_equal(Bool(true))
  })
}

///|
test "IS INTERVAL checks the fields and precisions of the qualifier" {
  @expect.expect_all(soft => {
    soft.expect(ev("INTERVAL '2' YEAR IS INTERVAL YEAR")).to_equal(Bool(true))
    soft.expect(ev("INTERVAL '2' YEAR IS INTERVAL MONTH")).to_equal(Bool(true))
    soft
    .expect(ev("INTERVAL '1-6' YEAR TO MONTH IS INTERVAL YEAR"))
    .to_equal(Bool(false))
    soft
    .expect(ev("INTERVAL '1-6' YEAR TO MONTH IS INTERVAL YEAR TO MONTH"))
    .to_equal(Bool(true))
    soft
    .expect(ev("INTERVAL '100' MONTH(3) IS INTERVAL MONTH"))
    .to_equal(Bool(false))
    soft
    .expect(ev("INTERVAL '100' MONTH(3) IS INTERVAL MONTH(3)"))
    .to_equal(Bool(true))
    soft.expect(ev("INTERVAL '1' DAY IS INTERVAL DAY")).to_equal(Bool(true))
    soft.expect(ev("INTERVAL '1' DAY IS INTERVAL HOUR")).to_equal(Bool(true))
    soft
    .expect(ev("INTERVAL '1:30' HOUR TO MINUTE IS INTERVAL DAY"))
    .to_equal(Bool(false))
    soft
    .expect(ev("INTERVAL '1:30' HOUR TO MINUTE IS INTERVAL HOUR"))
    .to_equal(Bool(false))
    soft
    .expect(ev("INTERVAL '1:30' HOUR TO MINUTE IS INTERVAL MINUTE"))
    .to_equal(Bool(true))
    soft
    .expect(ev("INTERVAL '100' DAY(3) IS INTERVAL DAY"))
    .to_equal(Bool(false))
    soft
    .expect(ev("INTERVAL '-100' DAY(3) IS INTERVAL DAY(3)"))
    .to_equal(Bool(true))
    soft
    .expect(ev("INTERVAL '1.5' SECOND IS INTERVAL SECOND(2, 0)"))
    .to_equal(Bool(false))
    soft
    .expect(ev("INTERVAL '1.5' SECOND IS INTERVAL SECOND(2, 1)"))
    .to_equal(Bool(true))
    soft
    .expect(ev("INTERVAL '1.5' SECOND IS INTERVAL SECOND"))
    .to_equal(Bool(true))
    soft.expect(ev("INTERVAL '1' DAY IS INTERVAL YEAR")).to_equal(Bool(false))
    soft.expect(ev("1 IS INTERVAL DAY")).to_equal(Bool(false))
  })
}

///|
test "a type parameter that IS does not check is unsupported" {
  @expect.expect_all(soft => {
    for
      source in [
        "1e0 IS FLOAT(10)", "[1] IS ARRAY<INT>", "MAP {'a': 1} IS MAP<VARCHAR(3), INT>",
        "MAP {'a': 1} IS MAP<STRING, DECIMAL(3, 1)>", "MAP {'a': 1} IS MAP<STRING, TIME WITH TIME ZONE>",
      ] {
      soft
      .expect_call(() => ev(source))
      .to_raise_matching(
        e => e is @eval.EvalError::Unsupported(..),
        description="Unsupported for \{source}",
      )
    }
    soft.expect(ev("[1] IS ARRAY")).to_equal(Bool(true))
    soft.expect(ev("MAP {'a': 1} IS MAP<STRING, INTEGER>")).to_equal(Bool(true))
  })
}

///|
test "IS with an interval qualifier that is not valid is a data error" {
  @expect.expect_all(soft => {
    for
      source in [
        "INTERVAL '1' DAY IS INTERVAL DAY TO MONTH", "INTERVAL '1' DAY IS INTERVAL MINUTE TO HOUR",
        "INTERVAL '1' SECOND IS INTERVAL SECOND(2, 12)",
      ] {
      soft
      .expect_call(() => ev(source))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError for \{source}",
      )
    }
  })
}
