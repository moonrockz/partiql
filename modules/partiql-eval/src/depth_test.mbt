///|
test "a long + chain evaluates without overflowing the stack" {
  let source = "1" + " + 1".repeat(99999)
  @expect.expect(ev(source)).to_equal(Int(100000))
}

///|
test "a long OR chain evaluates without overflowing the stack" {
  let env = @eval.Bindings::of_tuple(@value.Tuple::new([("x", Int(99999))]))
  let terms = Array::makei(100000, i => "x = \{i}")
  @expect.expect_all(soft => {
    soft
    .expect(@eval.evaluate_text(terms.join(" OR "), env~))
    .to_equal(Bool(true))
    soft
    .expect(@eval.evaluate_text(terms.join(" AND "), env~))
    .to_equal(Bool(false))
  })
}

///|
test "a long postfix chain is a data error, not a stack overflow" {
  @expect.expect_all(soft => {
    for depth in [201, 100000] {
      let deep = "1" + " IS NOT NULL".repeat(depth - 1)
      for mode in [@eval.Mode::Permissive, Strict] {
        soft
        .expect_call(() => ev(deep, mode~))
        .to_raise_matching(
          e => {
            e
            is @eval.EvalError::DataError(message="expression is too deep", ..)
          },
          description="DataError at depth \{depth}",
        )
      }
    }
  })
}

///|
test "an expression at the depth limit evaluates on every target" {
  @expect.expect_all(soft => {
    soft.expect(ev("1" + " IS NOT NULL".repeat(199))).to_equal(Bool(true))
    soft.expect(ev("TRUE" + " IS TRUE".repeat(199))).to_equal(Bool(true))
    soft
    .expect(ev("TRUE" + " BETWEEN FALSE AND TRUE".repeat(199)))
    .to_equal(Bool(true))
    // the list element is one level below the IN
    soft.expect(ev("TRUE" + " IN [TRUE]".repeat(198))).to_equal(Bool(true))
    // a chain link and a postfix operator: two levels each
    soft.expect(ev("1" + " = 1 IS NOT NULL".repeat(99))).to_equal(Bool(true))
  })
}

///|
test "deep Ion literals evaluate and compare without a data nesting limit" {
  let ion = (n : Int32) => "`" + "[".repeat(n) + "]".repeat(n) + "`"
  @expect.expect_all(soft => {
    for n in [128, 1000, 100000] {
      soft.expect(ev("\{ion(n)} = \{ion(n)}")).to_equal(Bool(true))
    }
  })
}

///|
test "lateral FROM can compare values nested at runtime" {
  let sources = ["[1] AS v0"]
  for i in 1..<=2000 {
    sources.push("[[v\{i - 1}]] AS v\{i}")
  }
  @expect.expect(ev("SELECT VALUE v2000 = v2000 FROM " + sources.join(", "))).to_equal(
    Bag(@value.Bag::new([Bool(true)])),
  )
}

///|
test "global values can be nested 100000 levels" {
  let mut v : @value.Value = Int(1)
  for _ in 0..<100000 {
    v = List([v])
  }
  let env = @eval.Bindings::of_tuple(@value.Tuple::new([("v", v)]))
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(@eval.evaluate_text("v = v", env~, mode~))
      .to_equal(Bool(true))
      soft
      .expect(@eval.evaluate_text("v IN [v]", env~, mode~))
      .to_equal(Bool(true))
      soft
      .expect_call(() => @eval.evaluate_text("MAP {v: 1}", env~, mode~))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(_),
        description="DataError for a non-scalar map key",
      )
    }
  })
}

///|
test "long chains in a grouped query do not overflow the stack" {
  let ones = " + 1".repeat(99999)
  let terms = Array::makei(100000, i => "k = \{i}")
  @expect.expect_all(soft => {
    soft
    .expect(
      ev(
        "SELECT k FROM [{'a': 1}] AS t GROUP BY t.a AS k HAVING " +
        terms.join(" OR "),
      ),
    )
    .to_equal(Bag(@value.Bag::new([Tuple(@value.Tuple::new([("k", Int(1))]))])))
    soft
    .expect(ev("SELECT VALUE t.a\{ones} FROM [{'a': 1}] AS t GROUP BY t.a"))
    .to_equal(Bag(@value.Bag::new([Int(100000)])))
    soft
    .expect(
      ev("SELECT VALUE SUM(t.a\{ones}) FROM [{'a': 1}] AS t GROUP BY t.a"),
    )
    .to_equal(Bag(@value.Bag::new([Int(100000)])))
    // A long key, repeated in SELECT.
    soft
    .expect(
      ev("SELECT VALUE t.a\{ones} FROM [{'a': 1}] AS t GROUP BY t.a\{ones}"),
    )
    .to_equal(Bag(@value.Bag::new([Int(100000)])))
  })
}
