///|
fn pretty_expr(source : String, width : Int) -> String raise {
  @printer.print(@parser.parse_statement(source), width~)
}

///|
test "expressions break at their layout points" {
  @expect.expect_all(soft => {
    soft
    .expect(
      pretty_expr(
        "SELECT a FROM t WHERE o.total > 100 AND o.status = 'open' AND o.region = 'eu'",
        40,
      ),
    )
    .to_equal(
      "SELECT a\nFROM t\nWHERE o.total > 100\n  AND o.status = 'open'\n  AND o.region = 'eu'",
    )
    soft
    .expect(
      pretty_expr("SELECT aaaaaaaaaa + bbbbbbbbbb + cccccccccc FROM t", 20),
    )
    .to_equal(
      "SELECT\n  aaaaaaaaaa\n    + bbbbbbbbbb\n    + cccccccccc\nFROM t",
    )
    soft
    .expect(pretty_expr("SELECT f(aaaaaaa, bbbbbbb, ccccccc)", 20))
    .to_equal("SELECT\n  f(\n    aaaaaaa,\n    bbbbbbb,\n    ccccccc\n  )")
    soft
    .expect(pretty_expr("SELECT COALESCE(aaaaaaa, bbbbbbb)", 20))
    .to_equal("SELECT\n  COALESCE(\n    aaaaaaa,\n    bbbbbbb\n  )")
    soft
    .expect(
      pretty_expr(
        "SELECT CASE WHEN a = 1 THEN 'one' WHEN a = 2 THEN 'two' ELSE 'many' END FROM t",
        30,
      ),
    )
    .to_equal(
      "SELECT\n  CASE\n    WHEN a = 1 THEN 'one'\n    WHEN a = 2 THEN 'two'\n    ELSE 'many'\n  END\nFROM t",
    )
    soft
    .expect(pretty_expr("[1111111, 2222222, 3333333]", 12))
    .to_equal("[\n  1111111,\n  2222222,\n  3333333\n]")
    soft
    .expect(pretty_expr("{'aaaa': 1111, 'bbbb': 2222}", 20))
    .to_equal("{\n  'aaaa': 1111,\n  'bbbb': 2222\n}")
    soft
    .expect(pretty_expr("VALUES (1, 2), (3, 4)", 12))
    .to_equal("VALUES\n  (1, 2),\n  (3, 4)")
    soft
    .expect(pretty_expr("(g MATCH (a) -[e]-> (b) -[f]-> (c))", 30))
    .to_equal("(g MATCH\n  (a) -[e]-> (b) -[f]-> (c))")
  })
}

///|
test "the width counts code points" {
  // 20 code points, 24 UTF-16 code units.
  let source = "SELECT '😀😀😀😀' FROM t"
  @expect.expect_all(soft => {
    soft.expect(pretty_expr(source, 20)).to_equal(source)
    soft
    .expect(pretty_expr(source, 19))
    .to_equal("SELECT '😀😀😀😀'\nFROM t")
  })
}
