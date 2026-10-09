///|
test "SELECT VALUE over a collection" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2, 3] AS x"))
    .to_equal(Bag(@value.Bag::new([Int(1), Int(2), Int(3)])))
    soft
    .expect(ev("SELECT VALUE x + 1 FROM <<1, 2>> AS x WHERE x > 1"))
    .to_equal(Bag(@value.Bag::new([Int(3)])))
    soft
    .expect(ev("SELECT VALUE x FROM [] AS x"))
    .to_equal(Bag(@value.Bag::new([])))
    // The corpus keeps MISSING (spec-tests.ion, "bag element evaluates to
    // MISSING").
    soft
    .expect(ev("SELECT VALUE x FROM [1, MISSING, 3] AS x"))
    .to_equal(Bag(@value.Bag::new([Int(1), Missing, Int(3)])))
    soft
    .expect(ev("SELECT VALUE x FROM [1, 2] AS x WHERE NULL"))
    .to_equal(Bag(@value.Bag::new([])))
    soft
    .expect(ev("SELECT VALUE v FROM 1 AS v"))
    .to_equal(Bag(@value.Bag::new([Int(1)])))
    soft
    .expect_call(() => ev("SELECT VALUE v FROM 1 AS v", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    soft
    .expect(ev("SELECT VALUE x FROM [1] AS x WHERE 'a'"))
    .to_equal(Bag(@value.Bag::new([])))
    soft
    .expect_call(() => ev("SELECT VALUE x FROM [1] AS x WHERE 'a'", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    soft
    .expect_call(() => ev("SELECT VALUE x FROM [1] AS x ORDER BY x"))
    .to_raise_matching(
      e => e is @eval.EvalError::Unsupported(..),
      description="Unsupported",
    )
  })
}

///|
test "a global collection and a local shadowing a global" {
  let env = @eval.Bindings::of_ion(@text.read_ion("{t: [1, 2], x: 99}"))
  @expect.expect_all(soft => {
    soft
    .expect(@eval.evaluate_text("SELECT VALUE x FROM t AS x", env~))
    .to_equal(Bag(@value.Bag::new([Int(1), Int(2)])))
    soft.expect(@eval.evaluate_text("x", env~)).to_equal(Int(99))
  })
}

///|
test "an error in a row ends the query" {
  @expect.expect_all(soft => {
    // Raised by a WHERE inside the rows of an inner query.
    soft
    .expect_call(() => {
      ev(
        "SELECT VALUE (SELECT VALUE y FROM [1] AS y WHERE y + 'a') FROM [1, 2] AS x",
        mode=Strict,
      )
    })
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    // Raised by the projection of a row.
    soft
    .expect_call(() => ev("SELECT VALUE 1 / x FROM [1, 0] AS x"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
  })
}

///|
test "a FROM variable without AS and a correlated subquery" {
  let env = @eval.Bindings::of_ion(@text.read_ion("{t: [1, 2], s: {u: [3]}}"))
  @expect.expect_all(soft => {
    soft
    .expect(@eval.evaluate_text("SELECT VALUE T FROM t", env~))
    .to_equal(Bag(@value.Bag::new([Int(1), Int(2)])))
    soft
    .expect(@eval.evaluate_text("SELECT VALUE u FROM s.u", env~))
    .to_equal(Bag(@value.Bag::new([Int(3)])))
    // `[1] + 1` is MISSING: one binding of `_1`.
    soft
    .expect(ev("SELECT VALUE _1 FROM [1] + 1"))
    .to_equal(Bag(@value.Bag::new([Missing])))
    soft
    .expect(
      ev(
        "SELECT VALUE (SELECT VALUE x + y FROM [10] AS y) FROM [1, 2] AS x WHERE x IN (SELECT VALUE z FROM [2] AS z)",
      ),
    )
    .to_equal(Bag(@value.Bag::new([Bag(@value.Bag::new([Int(12)]))])))
  })
}

///|
test "AT binds a list position" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE [i, x] FROM ['a', 'b'] AS x AT i"))
    .to_equal(
      Bag(
        @value.Bag::new([
          List([Int(0), String("a")]),
          List([Int(1), String("b")]),
        ]),
      ),
    )
    soft
    .expect(ev("SELECT VALUE i FROM <<'a'>> AS x AT i"))
    .to_equal(Bag(@value.Bag::new([Missing])))
    soft
    .expect_call(() => ev("SELECT VALUE i FROM <<'a'>> AS x AT i", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}
