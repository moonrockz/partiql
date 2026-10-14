///|
test "ORDER BY" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE x FROM [3, 1, 2] AS x ORDER BY x"))
    .to_equal(List([Int(1), Int(2), Int(3)]))
    soft
    .expect(ev("SELECT VALUE x FROM <<3, 1, 2>> AS x ORDER BY x DESC"))
    .to_equal(List([Int(3), Int(2), Int(1)]))
    // ASC: absent values last by default; DESC: first (plan ruling 1)
    soft
    .expect(ev("SELECT VALUE x FROM [2, NULL, 1] AS x ORDER BY x"))
    .to_equal(List([Int(1), Int(2), Null]))
    soft
    .expect(ev("SELECT VALUE x FROM [2, NULL, 1] AS x ORDER BY x DESC"))
    .to_equal(List([Null, Int(2), Int(1)]))
    soft
    .expect(ev("SELECT VALUE x FROM [2, NULL, 1] AS x ORDER BY x NULLS FIRST"))
    .to_equal(List([Null, Int(1), Int(2)]))
    soft
    .expect(
      ev("SELECT VALUE x FROM [2, NULL, 1] AS x ORDER BY x DESC NULLS LAST"),
    )
    .to_equal(List([Int(2), Int(1), Null]))
    // several keys
    soft
    .expect(
      ev(
        "SELECT VALUE [a, b] FROM [[1, 2], [0, 9], [1, 1]] AS r LET r[0] AS a, r[1] AS b ORDER BY a, b DESC",
      ),
    )
    .to_equal(
      List([
        List([Int(0), Int(9)]),
        List([Int(1), Int(2)]),
        List([Int(1), Int(1)]),
      ]),
    )
    // a key on an output alias, and on a FROM attribute that is not projected
    soft
    .expect(
      ev(
        "SELECT r.a AS k FROM [{'a': 2, 'b': 1}, {'a': 1, 'b': 2}] AS r ORDER BY k",
      ),
    )
    .to_equal(List([tuple([("k", Int(1))]), tuple([("k", Int(2))])]))
    soft
    .expect(
      ev(
        "SELECT r.a AS k FROM [{'a': 2, 'b': 1}, {'a': 1, 'b': 2}] AS r ORDER BY r.b",
      ),
    )
    .to_equal(List([tuple([("k", Int(2))]), tuple([("k", Int(1))])]))
    // an implicit name
    soft
    .expect(ev("SELECT * FROM [{'a': 2}, {'a': 1}] ORDER BY a"))
    .to_equal(List([tuple([("a", Int(1))]), tuple([("a", Int(2))])]))
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
      List([
        Bool(false),
        Int(5),
        String("a"),
        List([]),
        tuple([]),
        bag_of([]),
        Null,
      ]),
    )
    // the empty input
    soft.expect(ev("SELECT * FROM <<>> ORDER BY true")).to_equal(List([]))
    // a nested ORDER BY gives a list; the outer result stays a bag
    soft
    .expect(ev("SELECT (SELECT * FROM <<>> ORDER BY true) AS o FROM <<0>>"))
    .to_equal(bag_of([tuple([("o", List([]))])]))
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
    .to_equal(List([tuple([("x", Int(1))]), tuple([("x", Int(2))])]))
    // An output name is not a candidate for an implicit attribute: `a` is
    // `r.a`, not `t.a`
    soft
    .expect(
      ev(
        "SELECT r.n AS t FROM [{'a': 2, 'n': {'a': 1}}, {'a': 1, 'n': {'a': 2}}] AS r ORDER BY a",
      ),
    )
    .to_equal(
      List([
        tuple([("t", tuple([("a", Int(2))]))]),
        tuple([("t", tuple([("a", Int(1))]))]),
      ]),
    )
    // A body that is not a SELECT: a plain name is an attribute of the
    // element (plan ruling 11)
    soft
    .expect(ev("[{'a': 3}, {'a': 1}, {'a': 2}] ORDER BY a DESC"))
    .to_equal(
      List([
        tuple([("a", Int(3))]),
        tuple([("a", Int(2))]),
        tuple([("a", Int(1))]),
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
        List([Int(0), Int(1)]),
        List([Int(1), Int(2)]),
        List([Int(2), Int(3)]),
      ]),
    )
    // Review Focus 3: a key that fails is MISSING (sorted last, ASC) in permissive mode
    soft
    .expect(ev("SELECT VALUE x FROM [2, 'a', 1] AS x ORDER BY x + 1"))
    .to_equal(List([Int(1), Int(2), String("a")]))
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
    .to_equal(Bool(true))
    soft
    .expect(ev("2 IN (SELECT x FROM [1, 2] AS x ORDER BY x)"))
    .to_equal(Bool(true))
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
    soft.expect(ev(nested_ordered(30, in_key=false))).to_equal(Int(1))
    // The outermost query is the statement, which is not coerced.
    soft
    .expect(ev(nested_ordered(30, in_key=true)))
    .to_equal(List([tuple([("x", Int(1))])]))
  })
}
