///|
test "correlated subqueries" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev(
        "SELECT VALUE (SELECT VALUE y FROM [1, 2, 3] AS y WHERE y > x) FROM [1, 2] AS x",
      ),
    )
    .to_equal(
      bag_of([
        bag_of([@value.Value::from_int(2), @value.Value::from_int(3)]),
        bag_of([@value.Value::from_int(3)]),
      ]),
    )
  })
}

///|
test "SQL coercion of a single-column SELECT" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("1 = (SELECT x FROM [1] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("(SELECT x FROM [] AS x) IS NULL"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("1 + (SELECT x FROM [2] AS x)"))
    .to_equal(@value.Value::from_int(3))
    // more than one row: MISSING in permissive mode (spec-tests section 10),
    // a TypeError in strict mode
    soft
    .expect(ev("(SELECT x FROM [1, 2] AS x) IS MISSING"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect_call(() => ev("1 = (SELECT x FROM [1, 2] AS x)", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    // SELECT VALUE is never coerced
    soft
    .expect(ev("1 = (SELECT VALUE x FROM [1] AS x)"))
    .to_equal(@value.Value::from_bool(false))
    // a SELECT item is a coercion context (spec-tests section 10)
    soft
    .expect(
      ev(
        "SELECT o.n AS n, (SELECT c.name FROM [{'id': 1, 'name': 'Mary'}, {'id': 1, 'name': 'John'}, {'id': 2, 'name': 'Helen'}] AS c WHERE c.id = o.id) AS name FROM [{'n': 'foo', 'id': 1}, {'n': 'bar', 'id': 2}] AS o",
      ),
    )
    .to_equal(
      bag_of([
        tuple([("n", @value.Value::from_string("foo"))]),
        tuple([
          ("n", @value.Value::from_string("bar")),
          ("name", @value.Value::from_string("Helen")),
        ]),
      ]),
    )
    // two columns are not coerced
    soft
    .expect(ev("(SELECT x, x AS y FROM [1] AS x) IS NULL"))
    .to_equal(@value.Value::from_bool(false))
  })
}

///|
test "IN with a subquery and VALUES" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("2 IN (SELECT x FROM [1, 2] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("3 NOT IN (SELECT x FROM [1, 2] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("2 IN (SELECT VALUE x FROM [1, 2] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("VALUES (1, 2), (3, 4)"))
    .to_equal(
      bag_of([
        @value.Value::from_list([
          @value.Value::from_int(1),
          @value.Value::from_int(2),
        ]),
        @value.Value::from_list([
          @value.Value::from_int(3),
          @value.Value::from_int(4),
        ]),
      ]),
    )
    // a one-column row is still a list (basic.ion)
    soft
    .expect(ev("VALUES (1), (2, 3)"))
    .to_equal(
      bag_of([
        @value.Value::from_list([@value.Value::from_int(1)]),
        @value.Value::from_list([
          @value.Value::from_int(2),
          @value.Value::from_int(3),
        ]),
      ]),
    )
    soft
    .expect(ev("(1, 2) IN (VALUES (1, 2), (3, 4))"))
    .to_equal(@value.Value::from_bool(true))
  })
}

///|
fn nested_subqueries(levels : Int32) -> String {
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
  @expect.expect(ev(nested_subqueries(30))).to_equal(@value.Value::from_int(1))
}

///|
test "a single-column SELECT is coerced in every position but FROM, IN and the top" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("(SELECT x FROM [true] AS x) AND true"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("true AND (SELECT x FROM [true] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("(SELECT x FROM [false] AS x) OR true"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("false OR (SELECT x FROM [true] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("NOT (SELECT x FROM [false] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(
      ev("SELECT VALUE y FROM [1, 2] AS y WHERE (SELECT x FROM [true] AS x)"),
    )
    .to_equal(bag_of([@value.Value::from_int(1), @value.Value::from_int(2)]))
    soft
    .expect(
      ev("SELECT VALUE z FROM [1] AS y LET (SELECT x FROM [7] AS x) AS z"),
    )
    .to_equal(bag_of([@value.Value::from_int(7)]))
    soft
    .expect(ev("SELECT VALUE (SELECT x FROM [5] AS x) FROM [1] AS y"))
    .to_equal(bag_of([@value.Value::from_int(5)]))
    soft
    .expect(ev("[(SELECT x FROM [5] AS x)]"))
    .to_equal(@value.Value::from_list([@value.Value::from_int(5)]))
    soft
    .expect(ev("(SELECT x FROM [{'a': 3}] AS x).a"))
    .to_equal(@value.Value::from_int(3))
    // not coerced: FROM sources, the right side of IN, the statement
    soft
    .expect(ev("SELECT VALUE y FROM (SELECT x FROM [5] AS x) AS y"))
    .to_equal(bag_of([tuple([("x", @value.Value::from_int(5))])]))
    soft
    .expect(ev("SELECT x FROM [5] AS x"))
    .to_equal(bag_of([tuple([("x", @value.Value::from_int(5))])]))
    soft
    .expect(ev("(SELECT x FROM [5] AS x)"))
    .to_equal(bag_of([tuple([("x", @value.Value::from_int(5))])]))
    soft
    .expect(ev("5 IN (SELECT x FROM [5] AS x)"))
    .to_equal(@value.Value::from_bool(true))
  })
}

///|
test "array coercion of a SELECT subquery (plan ruling 9)" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("[1, 2] = (SELECT x.a, x.b FROM [{'a': 1, 'b': 2}] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("(1, 2) = (SELECT x.a, x.b FROM [{'a': 1, 'b': 2}] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("(SELECT x.a, x.b FROM [{'a': 1, 'b': 3}] AS x) = (1, 2)"))
    .to_equal(@value.Value::from_bool(false))
    soft
    .expect(ev("[1] = (SELECT x FROM [1] AS x)"))
    .to_equal(@value.Value::from_bool(true))
    // no row: NULL; two rows: MISSING (permissive), TypeError (strict)
    soft.expect(ev("[1] = (SELECT x FROM [] AS x)")).to_equal(Null)
    soft.expect(ev("[1] = (SELECT x FROM [1, 2] AS x)")).to_equal(Missing)
    soft
    .expect_call(() => ev("[1] = (SELECT x FROM [1, 2] AS x)", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    // SELECT VALUE is not coerced
    soft
    .expect(ev("[1] = (SELECT VALUE x FROM [1] AS x)"))
    .to_equal(@value.Value::from_bool(false))
  })
}

///|
test "array coercion with an Ion list or s-expression literal" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("(SELECT x.a, x.b FROM [{'a': 1, 'b': 2}] AS x) = `[1, 2]`"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("`(1 2)` = (SELECT x.a, x.b FROM [{'a': 1, 'b': 2}] AS x)"))
    .to_equal(@value.Value::from_bool(true))
  })
}
