///|
test "correlated subqueries" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev(
        "SELECT VALUE (SELECT VALUE y FROM [1, 2, 3] AS y WHERE y > x) FROM [1, 2] AS x",
      ),
    )
    .to_equal(bag_of([bag_of([Int(2), Int(3)]), bag_of([Int(3)])]))
  })
}

///|
test "SQL coercion of a single-column SELECT" {
  @expect.expect_all(soft => {
    soft.expect(ev("1 = (SELECT x FROM [1] AS x)")).to_equal(Bool(true))
    soft.expect(ev("(SELECT x FROM [] AS x) IS NULL")).to_equal(Bool(true))
    soft.expect(ev("1 + (SELECT x FROM [2] AS x)")).to_equal(Int(3))
    // more than one row: MISSING in permissive mode (spec-tests section 10),
    // a DataError in strict mode
    soft
    .expect(ev("(SELECT x FROM [1, 2] AS x) IS MISSING"))
    .to_equal(Bool(true))
    soft
    .expect_call(() => ev("1 = (SELECT x FROM [1, 2] AS x)", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    // SELECT VALUE is never coerced
    soft.expect(ev("1 = (SELECT VALUE x FROM [1] AS x)")).to_equal(Bool(false))
    // a SELECT item is a coercion context (spec-tests section 10)
    soft
    .expect(
      ev(
        "SELECT o.n AS n, (SELECT c.name FROM [{'id': 1, 'name': 'Mary'}, {'id': 1, 'name': 'John'}, {'id': 2, 'name': 'Helen'}] AS c WHERE c.id = o.id) AS name FROM [{'n': 'foo', 'id': 1}, {'n': 'bar', 'id': 2}] AS o",
      ),
    )
    .to_equal(
      bag_of([
        tuple([("n", String("foo"))]),
        tuple([("n", String("bar")), ("name", String("Helen"))]),
      ]),
    )
    // two columns are not coerced
    soft
    .expect(ev("(SELECT x, x AS y FROM [1] AS x) IS NULL"))
    .to_equal(Bool(false))
  })
}

///|
test "IN with a subquery and VALUES" {
  @expect.expect_all(soft => {
    soft.expect(ev("2 IN (SELECT x FROM [1, 2] AS x)")).to_equal(Bool(true))
    soft.expect(ev("3 NOT IN (SELECT x FROM [1, 2] AS x)")).to_equal(Bool(true))
    soft
    .expect(ev("2 IN (SELECT VALUE x FROM [1, 2] AS x)"))
    .to_equal(Bool(true))
    soft
    .expect(ev("VALUES (1, 2), (3, 4)"))
    .to_equal(bag_of([List([Int(1), Int(2)]), List([Int(3), Int(4)])]))
    // a one-column row is still a list (basic.ion)
    soft
    .expect(ev("VALUES (1), (2, 3)"))
    .to_equal(bag_of([List([Int(1)]), List([Int(2), Int(3)])]))
    soft.expect(ev("(1, 2) IN (VALUES (1, 2), (3, 4))")).to_equal(Bool(true))
  })
}

///|
fn nested_subqueries(levels : Int) -> String {
  let mut s = "1"
  for _ in 0..<levels {
    s = "(SELECT x FROM [" + s + "] AS x) + 0"
  }
  s
}

///|
test "nested coerced subqueries evaluate on every target" {
  // The parser limits the nesting before the depth guard can (more than about
  // 40 levels is a syntax error).
  @expect.expect(ev(nested_subqueries(30))).to_equal(Int(1))
}
