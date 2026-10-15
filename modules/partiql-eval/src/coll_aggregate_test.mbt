///|
test "COLL_ functions over collections" {
  let numbers = "[1, 2.0, `3e0`, 4, 5.]"
  @expect.expect_all(soft => {
    soft.expect(ev("COLL_COUNT(<<1, 'x', NULL, MISSING>>)")).to_equal(Int(2))
    soft.expect(ev("COLL_COUNT(<< >>)")).to_equal(Int(0))
    soft.expect(ev("COLL_COUNT([MISSING])")).to_equal(Int(0))
    soft
    .expect(ev("COLL_SUM(\{numbers})"))
    .to_equal(Decimal(@ion.Decimal::parse("15.0")))
    soft
    .expect(ev("COLL_AVG(\{numbers})"))
    .to_equal(Decimal(@ion.Decimal::parse("3.0")))
    soft
    .expect(ev("COLL_AVG([2, 2, 2, 4])"))
    .to_equal(Decimal(@ion.Decimal::parse("2.5")))
    soft
    .expect(ev("COLL_MAX(\{numbers})"))
    .to_equal(Decimal(@ion.Decimal::parse("5.")))
    soft
    .expect(ev("COLL_MAX(<<1, 'non-number', NULL, MISSING>>)"))
    .to_equal(String("non-number"))
    soft
    .expect(ev("COLL_MIN(<<1, 'non-number', NULL, MISSING>>)"))
    .to_equal(Int(1))
    soft.expect(ev("COLL_SUM(<< >>)")).to_equal(Null)
    soft.expect(ev("COLL_AVG(<<MISSING, MISSING>>)")).to_equal(Null)
    soft.expect(ev("COLL_ANY(<< >>)")).to_equal(Null)
    soft.expect(ev("COLL_SOME(<<false, true>>)")).to_equal(Bool(true))
    soft
    .expect(ev("COLL_EVERY(<< NULL, 2 < 3, MISSING, true >>)"))
    .to_equal(Bool(true))
    soft.expect(ev("COLL_SUM(DISTINCT [1, 1, 1, 2])")).to_equal(Int(3))
    soft
    .expect(ev("COLL_AVG(DISTINCT [1, 1, 1, 2])"))
    .to_equal(Decimal(@ion.Decimal::parse("1.5")))
    soft.expect(ev("COLL_COUNT(ALL [1, 1])")).to_equal(Int(2))
    soft.expect(ev("coll_count([1])")).to_equal(Int(1))
    soft.expect(ev("COLL_SUM([`null.int`, 1])")).to_equal(Int(1))
  })
}

///|
test "COLL_ functions on NULL, MISSING and wrong input" {
  @expect.expect_all(soft => {
    soft.expect(ev("COLL_COUNT(NULL)")).to_equal(Null)
    soft.expect(ev("COLL_COUNT(MISSING)")).to_equal(Missing)
    soft.expect(ev("COLL_SUM(1)")).to_equal(Missing)
    soft.expect(ev("COLL_SUM(<<1, 'non-number'>>)")).to_equal(Missing)
    soft.expect(ev("COLL_ANY(<< true, 5, true >>)")).to_equal(Missing)
    for
      text in [
        "COLL_SUM(1)", "COLL_SUM(<<1, 'non-number'>>)", "COLL_ANY(<< true, 5 >>)",
      ] {
      soft
      .expect_call(() => ev(text, mode=Strict))
      .to_raise_matching(
        e => e is @eval.EvalError::TypeError(..),
        description="TypeError for \{text}",
      )
    }
    for text in ["COLL_SUM(1, 2)", "COLL_COUNT()", "COLL_COUNT(*)"] {
      soft
      .expect_call(() => ev(text))
      .to_raise_matching(
        e => {
          e is @eval.EvalError::DataError(..) || e is @eval.EvalError::Syntax(_)
        },
        description="static error for \{text}",
      )
    }
  })
}

///|
test "COLL_ functions in queries" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev("SELECT VALUE COLL_COUNT(v) + COLL_SUM(v) FROM <<[1, 2], [3]>> AS v"),
    )
    .to_equal(bag_of([Int(5), Int(4)]))
    soft
    .expect(ev("COLL_SUM(SELECT VALUE x FROM [1, 2, 3] AS x)"))
    .to_equal(Int(6))
  })
}
