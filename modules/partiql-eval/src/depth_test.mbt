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
test "a deep Ion literal is a data error, not a stack overflow" {
  let ion = (n : Int) => "`" + "[".repeat(n) + "]".repeat(n) + "`"
  @expect.expect_all(soft => {
    soft
    .expect_call(() => ev("\{ion(1000)} = \{ion(1000)}"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(message="expression is too deep", ..),
      description="DataError: expression is too deep",
    )
    soft.expect(ev("\{ion(150)} = \{ion(150)}")).to_equal(Bool(true))
  })
}
