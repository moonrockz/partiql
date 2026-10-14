///|
/// Evaluates `source` with a few bindings for TABLE and WITH.
fn wq(source : String) -> @value.Value raise {
  let env = @eval.Bindings::of_ion(
    @text.read_ion(
      "{t: $bag::[{a: 1}, {a: 2}], hr: {emp: $bag::[{n: 1}]}, w: 99}",
    ),
  )
  @eval.evaluate_text(source, env~, mode=Permissive)
}

///|
test "TABLE and WITH" {
  @expect.expect_all(soft => {
    soft
    .expect(wq("TABLE t"))
    .to_equal(bag_of([tuple([("a", Int(1))]), tuple([("a", Int(2))])]))
    soft.expect(wq("TABLE hr.emp")).to_equal(bag_of([tuple([("n", Int(1))])]))
    soft
    .expect(
      wq("WITH w AS (SELECT VALUE r.a FROM t AS r) SELECT VALUE x FROM w AS x"),
    )
    .to_equal(bag_of([Int(1), Int(2)]))
    // chained bindings
    soft
    .expect(
      wq(
        "WITH a AS (SELECT VALUE 1 FROM [0] AS z), b AS (SELECT VALUE x + 1 FROM a AS x) SELECT VALUE y FROM b AS y",
      ),
    )
    .to_equal(bag_of([Int(2)]))
    // a WITH name hides a global, also in a FROM source and in an expression
    soft
    .expect(
      wq("WITH w AS (SELECT VALUE 5 FROM [0] AS z) SELECT VALUE x FROM w AS x"),
    )
    .to_equal(bag_of([Int(5)]))
    soft
    .expect(
      wq(
        "WITH w AS (SELECT VALUE 5 FROM [0] AS z) SELECT VALUE w FROM [0] AS z",
      ),
    )
    .to_equal(bag_of([bag_of([Int(5)])]))
    // a repeated name is a DataError
    soft
    .expect_call(() => wq("WITH a AS (TABLE t), a AS (TABLE t) TABLE a"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    // ORDER BY over TABLE (a SELECT * body) sorts by an implicit attribute
    soft
    .expect(wq("TABLE t ORDER BY a DESC"))
    .to_equal(List([tuple([("a", Int(2))]), tuple([("a", Int(1))])]))
    // WITH wraps ORDER BY and LIMIT of the body
    soft
    .expect(
      wq(
        "WITH s AS (TABLE t) SELECT VALUE x.a FROM s AS x ORDER BY x.a DESC LIMIT 1",
      ),
    )
    .to_equal(List([Int(2)]))
  })
}
