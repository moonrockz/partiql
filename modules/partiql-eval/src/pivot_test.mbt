///|
test "PIVOT" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev("PIVOT x.v AT x.k FROM [{'k': 'a', 'v': 1}, {'k': 'b', 'v': 2}] AS x"),
    )
    .to_equal(
      tuple([("a", @value.Value::from_int(1)), ("b", @value.Value::from_int(2))]),
    )
    // duplicate keys are kept (pivot.ion pivotLiteralFieldNameFrom)
    soft
    .expect(ev("PIVOT x AT 'n' FROM [1, 2] AS x"))
    .to_equal(
      tuple([("n", @value.Value::from_int(1)), ("n", @value.Value::from_int(2))]),
    )
    // a MISSING value leaves the attribute out
    soft
    .expect(ev("PIVOT x.v AT x.k FROM [{'k': 'a'}, {'k': 'b', 'v': 2}] AS x"))
    .to_equal(tuple([("b", @value.Value::from_int(2))]))
    // a key that is not text: skipped in permissive mode, a TypeError in
    // strict mode (pivotBadFieldType)
    soft
    .expect(ev("PIVOT x AT i FROM ['a', 'b'] AS x AT i"))
    .to_equal(tuple([]))
    soft
    .expect_call(() => ev("PIVOT x AT i FROM ['a', 'b'] AS x AT i", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    // a symbol key is text
    soft
    .expect(ev("PIVOT 1 AT `s` FROM [0] AS x"))
    .to_equal(tuple([("s", @value.Value::from_int(1))]))
    // ORDER BY and LIMIT apply to the rows before PIVOT (limitoffset.ion
    // "offset with pivot")
    soft
    .expect(
      ev(
        "PIVOT foo.a AT foo.b FROM <<{'a': 1, 'b': 'I'}, {'a': 2, 'b': 'II'}, {'a': 3, 'b': 'III'}>> AS foo ORDER BY a LIMIT 1 OFFSET 1",
      ),
    )
    .to_equal(tuple([("II", @value.Value::from_int(2))]))
    // no rows: the empty tuple
    soft.expect(ev("PIVOT x AT 'a' FROM [] AS x")).to_equal(tuple([]))
  })
}
