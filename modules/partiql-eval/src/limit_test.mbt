///|
test "LIMIT and OFFSET" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2, 3, 4] AS x ORDER BY x LIMIT 2"))
    .to_equal(List([Int(1), Int(2)]))
    soft
    .expect(
      ev("SELECT VALUE x FROM [1, 2, 3, 4] AS x ORDER BY x LIMIT 2 OFFSET 1"),
    )
    .to_equal(List([Int(2), Int(3)]))
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2, 3, 4] AS x ORDER BY x OFFSET 3"))
    .to_equal(List([Int(4)]))
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2] AS x ORDER BY x LIMIT 0"))
    .to_equal(List([]))
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2] AS x ORDER BY x OFFSET 5"))
    .to_equal(List([]))
    // without ORDER BY the result stays a bag
    soft
    .expect(ev("SELECT VALUE x FROM <<7>> AS x LIMIT 5"))
    .to_equal(bag_of([Int(7)]))
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2, 3] AS x OFFSET 9223372036854775808"))
    .to_equal(bag_of([]))
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2, 3] AS x LIMIT 9223372036854775808"))
    .to_equal(bag_of([Int(1), Int(2), Int(3)]))
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2, 3] AS x LIMIT 2 OFFSET 1"))
    .to_equal(bag_of([Int(2), Int(3)]))
    // an expression
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2, 3, 4] AS x ORDER BY x OFFSET 4 / 2"))
    .to_equal(List([Int(3), Int(4)]))
    // LIMIT after DISTINCT; LIMIT reads an outer variable
    soft
    .expect(
      ev("SELECT DISTINCT VALUE x FROM [1, 1, 2, 2, 3] AS x ORDER BY x LIMIT 2"),
    )
    .to_equal(List([Int(1), Int(2)]))
    soft
    .expect(ev("SELECT DISTINCT VALUE x FROM [1, 1, 2, 2, 3] AS x LIMIT 2"))
    .to_equal(bag_of([Int(1), Int(2)]))
    soft
    .expect(
      ev(
        "SELECT VALUE (SELECT VALUE y FROM [1, 2, 3] AS y ORDER BY y LIMIT n) FROM [1, 2] AS n",
      ),
    )
    .to_equal(bag_of([List([Int(1)]), List([Int(1), Int(2)])]))
    // LIMIT stops reading: the rows after it are not evaluated
    soft
    .expect(ev("SELECT VALUE 1 / x FROM [1, 0] AS x LIMIT 1", mode=Strict))
    .to_equal(bag_of([Int(1)]))
  })
}

///|
test "LIMIT and OFFSET: invalid values (plan ruling 3)" {
  let all = bag_of([Int(1), Int(2), Int(3)])
  @expect.expect_all(soft => {
    // a negative literal fails in both modes
    soft
    .expect_call(() => ev("SELECT VALUE x FROM [1, 2, 3] AS x OFFSET -1"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    soft
    .expect_call(() => {
      ev("SELECT VALUE x FROM [1, 2, 3] AS x LIMIT -1", mode=Strict)
    })
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    // any other invalid value: permissive ignores the clause, strict fails
    for
      clause in [
        "OFFSET 1-2", "OFFSET 'x'", "OFFSET 2.5", "LIMIT NULL", "LIMIT 1-2",
      ] {
      soft
      .expect(ev("SELECT VALUE x FROM [1, 2, 3] AS x \{clause}"))
      .to_equal(all)
      soft
      .expect_call(() => {
        ev("SELECT VALUE x FROM [1, 2, 3] AS x \{clause}", mode=Strict)
      })
      .to_raise_matching(
        e => e is @eval.EvalError::TypeError(..),
        description="TypeError",
      )
    }
  })
}
