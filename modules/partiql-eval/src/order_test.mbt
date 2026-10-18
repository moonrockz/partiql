///|
test "ORDER BY" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE x FROM [3, 1, 2] AS x ORDER BY x"))
    .to_equal(
      @value.Value::from_list([
        @value.Value::from_int(1),
        @value.Value::from_int(2),
        @value.Value::from_int(3),
      ]),
    )
    soft
    .expect(ev("SELECT VALUE x FROM <<3, 1, 2>> AS x ORDER BY x DESC"))
    .to_equal(
      @value.Value::from_list([
        @value.Value::from_int(3),
        @value.Value::from_int(2),
        @value.Value::from_int(1),
      ]),
    )
    // ASC: absent values last by default; DESC: first (plan ruling 1)
    soft
    .expect(ev("SELECT VALUE x FROM [2, NULL, 1] AS x ORDER BY x"))
    .to_equal(
      @value.Value::from_list([
        @value.Value::from_int(1),
        @value.Value::from_int(2),
        Null,
      ]),
    )
    soft
    .expect(ev("SELECT VALUE x FROM [2, NULL, 1] AS x ORDER BY x DESC"))
    .to_equal(
      @value.Value::from_list([
        Null,
        @value.Value::from_int(2),
        @value.Value::from_int(1),
      ]),
    )
    soft
    .expect(ev("SELECT VALUE x FROM [2, NULL, 1] AS x ORDER BY x NULLS FIRST"))
    .to_equal(
      @value.Value::from_list([
        Null,
        @value.Value::from_int(1),
        @value.Value::from_int(2),
      ]),
    )
    soft
    .expect(
      ev("SELECT VALUE x FROM [2, NULL, 1] AS x ORDER BY x DESC NULLS LAST"),
    )
    .to_equal(
      @value.Value::from_list([
        @value.Value::from_int(2),
        @value.Value::from_int(1),
        Null,
      ]),
    )
    // several keys
    soft
    .expect(
      ev(
        "SELECT VALUE [a, b] FROM [[1, 2], [0, 9], [1, 1]] AS r LET r[0] AS a, r[1] AS b ORDER BY a, b DESC",
      ),
    )
    .to_equal(
      @value.Value::from_list([
        @value.Value::from_list([
          @value.Value::from_int(0),
          @value.Value::from_int(9),
        ]),
        @value.Value::from_list([
          @value.Value::from_int(1),
          @value.Value::from_int(2),
        ]),
        @value.Value::from_list([
          @value.Value::from_int(1),
          @value.Value::from_int(1),
        ]),
      ]),
    )
    // a key on an output alias, and on a FROM attribute that is not projected
    soft
    .expect(
      ev(
        "SELECT r.a AS k FROM [{'a': 2, 'b': 1}, {'a': 1, 'b': 2}] AS r ORDER BY k",
      ),
    )
    .to_equal(
      @value.Value::from_list([
        tuple([("k", @value.Value::from_int(1))]),
        tuple([("k", @value.Value::from_int(2))]),
      ]),
    )
    soft
    .expect(
      ev(
        "SELECT r.a AS k FROM [{'a': 2, 'b': 1}, {'a': 1, 'b': 2}] AS r ORDER BY r.b",
      ),
    )
    .to_equal(
      @value.Value::from_list([
        tuple([("k", @value.Value::from_int(2))]),
        tuple([("k", @value.Value::from_int(1))]),
      ]),
    )
    // an implicit name
    soft
    .expect(ev("SELECT * FROM [{'a': 2}, {'a': 1}] ORDER BY a"))
    .to_equal(
      @value.Value::from_list([
        tuple([("a", @value.Value::from_int(1))]),
        tuple([("a", @value.Value::from_int(2))]),
      ]),
    )
    // ties keep their input order (1, 1.0 and 1e0 are equal)
    soft
    .expect(ev("SELECT VALUE x FROM [1.0, 1, 0, 1e0] AS x ORDER BY x"))
    .to_equal(ev("[0, 1.0, 1, 1e0]"))
    // the mixed-type order: bool, numbers, text, list, struct, bag, then absent
    soft
    .expect(
      ev(
        "SELECT VALUE x FROM [<<>>, {}, [], 'a', 5, false, NULL] AS x ORDER BY x",
      ),
    )
    .to_equal(
      @value.Value::from_list([
        @value.Value::from_bool(false),
        @value.Value::from_int(5),
        @value.Value::from_string("a"),
        @value.Value::from_list([]),
        tuple([]),
        bag_of([]),
        Null,
      ]),
    )
    // the empty input
    soft
    .expect(ev("SELECT * FROM <<>> ORDER BY true"))
    .to_equal(@value.Value::from_list([]))
    // a nested ORDER BY gives a list; the outer result stays a bag
    soft
    .expect(ev("SELECT (SELECT * FROM <<>> ORDER BY true) AS o FROM <<0>>"))
    .to_equal(bag_of([tuple([("o", @value.Value::from_list([]))])]))
  })
}

///|
test "ORDER BY: alias wins over an attribute, AT over an ordered subquery, failing keys" {
  @expect.expect_all(soft => {
    // Review Focus 1
    soft
    .expect(
      ev(
        "SELECT r.y AS x FROM [{'x': 1, 'y': 2}, {'x': 2, 'y': 1}] AS r ORDER BY x",
      ),
    )
    .to_equal(
      @value.Value::from_list([
        tuple([("x", @value.Value::from_int(1))]),
        tuple([("x", @value.Value::from_int(2))]),
      ]),
    )
    // An output name is not a candidate for an implicit attribute: `a` is
    // `r.a`, not `t.a`
    soft
    .expect(
      ev(
        "SELECT r.n AS t FROM [{'a': 2, 'n': {'a': 1}}, {'a': 1, 'n': {'a': 2}}] AS r ORDER BY a",
      ),
    )
    .to_equal(
      @value.Value::from_list([
        tuple([("t", tuple([("a", @value.Value::from_int(2))]))]),
        tuple([("t", tuple([("a", @value.Value::from_int(1))]))]),
      ]),
    )
    // A body that is not a SELECT: a plain name is an attribute of the
    // element (plan ruling 11)
    soft
    .expect(ev("[{'a': 3}, {'a': 1}, {'a': 2}] ORDER BY a DESC"))
    .to_equal(
      @value.Value::from_list([
        tuple([("a", @value.Value::from_int(3))]),
        tuple([("a", @value.Value::from_int(2))]),
        tuple([("a", @value.Value::from_int(1))]),
      ]),
    )
    // Review Focus 2
    soft
    .expect(
      ev(
        "SELECT VALUE [i, x] FROM (SELECT VALUE v FROM [3, 1, 2] AS v ORDER BY v) AS x AT i",
      ),
    )
    .to_equal(
      bag_of([
        @value.Value::from_list([
          @value.Value::from_int(0),
          @value.Value::from_int(1),
        ]),
        @value.Value::from_list([
          @value.Value::from_int(1),
          @value.Value::from_int(2),
        ]),
        @value.Value::from_list([
          @value.Value::from_int(2),
          @value.Value::from_int(3),
        ]),
      ]),
    )
    // Review Focus 3: a key that fails is MISSING (sorted last, ASC) in permissive mode
    soft
    .expect(ev("SELECT VALUE x FROM [2, 'a', 1] AS x ORDER BY x + 1"))
    .to_equal(
      @value.Value::from_list([
        @value.Value::from_int(1),
        @value.Value::from_int(2),
        @value.Value::from_string("a"),
      ]),
    )
    soft
    .expect_call(() => {
      ev("SELECT VALUE x FROM [2, 'a', 1] AS x ORDER BY x + 1", mode=Strict)
    })
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    // a subquery with ORDER BY in a coercion context is one row per element (M4b1 minor)
    soft
    .expect(ev("1 = (SELECT x FROM [1] AS x ORDER BY x)"))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(ev("2 IN (SELECT x FROM [1, 2] AS x ORDER BY x)"))
    .to_equal(@value.Value::from_bool(true))
  })
}

///|
/// `levels` nested subqueries with ORDER BY, each in the FROM of the next
/// (`in_key` false) or in its sort key (`in_key` true).
fn nested_ordered(levels : Int32, in_key~ : Bool) -> String {
  let mut s = "1"
  for _ in 0..<levels {
    s = if in_key {
      "(SELECT x FROM [1] AS x ORDER BY " + s + ")"
    } else {
      "(SELECT x FROM [" + s + "] AS x ORDER BY x) + 0"
    }
  }
  s
}

///|
test "nested subqueries with ORDER BY evaluate on every target" {
  @expect.expect_all(soft => {
    soft
    .expect(ev(nested_ordered(30, in_key=false)))
    .to_equal(@value.Value::from_int(1))
    // The outermost query is the statement, which is not coerced.
    soft
    .expect(ev(nested_ordered(30, in_key=true)))
    .to_equal(
      @value.Value::from_list([tuple([("x", @value.Value::from_int(1))])]),
    )
  })
}

///|
test "ORDER BY: a variable beats an alias inside a non-bare key" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, @eval.Mode::Strict] {
      // `x.b` is the FROM variable, not the alias `x`
      soft
      .expect(
        ev(
          "SELECT x.a AS x FROM [{'a': 2, 'b': 1}, {'a': 1, 'b': 2}] AS x ORDER BY x.b",
          mode~,
        ),
      )
      .to_equal(
        @value.Value::from_list([
          tuple([("x", @value.Value::from_int(2))]),
          tuple([("x", @value.Value::from_int(1))]),
        ]),
      )
      // a bare name still finds the alias first
      soft
      .expect(
        ev(
          "SELECT r.y AS x FROM [{'x': 1, 'y': 2}, {'x': 2, 'y': 1}] AS r ORDER BY x",
          mode~,
        ),
      )
      .to_equal(
        @value.Value::from_list([
          tuple([("x", @value.Value::from_int(1))]),
          tuple([("x", @value.Value::from_int(2))]),
        ]),
      )
      // an alias that no variable hides is visible in a larger key
      soft
      .expect(
        ev(
          "SELECT r.a AS k FROM [{'a': 2}, {'a': 1}] AS r ORDER BY k * 1",
          mode~,
        ),
      )
      .to_equal(
        @value.Value::from_list([
          tuple([("k", @value.Value::from_int(1))]),
          tuple([("k", @value.Value::from_int(2))]),
        ]),
      )
    }
  })
}
