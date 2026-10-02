///|
fn pretty(source : String, width : Int) -> String raise {
  @printer.print(@parser.parse_statement(source), width~)
}

///|
test "queries break into clauses when they do not fit" {
  let long = "SELECT o.id, o.total, c.name, c.email FROM orders AS o JOIN customers AS c ON o.customer_id = c.id WHERE o.total > 100 AND o.status = 'open' ORDER BY o.total DESC"
  @expect.expect_all(soft => {
    soft
    .expect(pretty("select a, b from t where x = 1", 30))
    .to_equal("SELECT a, b FROM t WHERE x = 1")
    soft
    .expect(pretty("select a, b from t where x = 1", 29))
    .to_equal("SELECT a, b\nFROM t\nWHERE x = 1")
    soft
    .expect(pretty(long, 50))
    .to_equal(
      (
        #|SELECT o.id, o.total, c.name, c.email
        #|FROM orders AS o
        #|  JOIN customers AS c ON o.customer_id = c.id
        #|WHERE o.total > 100 AND o.status = 'open'
        #|ORDER BY o.total DESC
      ),
    )
    soft
    .expect(pretty("SELECT aaaa, bbbb, cccc, dddd, eeee FROM t", 30))
    .to_equal("SELECT\n  aaaa,\n  bbbb,\n  cccc,\n  dddd,\n  eeee\nFROM t")
    soft
    .expect(pretty("SELECT a FROM (SELECT b FROM u WHERE c = 1) AS s", 30))
    .to_equal("SELECT a\nFROM (\n  SELECT b FROM u WHERE c = 1\n) AS s")
    soft
    .expect(pretty("SELECT a FROM t UNION ALL SELECT b FROM u", 30))
    .to_equal("SELECT a FROM t\nUNION ALL\nSELECT b FROM u")
    soft
    .expect(pretty("SELECT a FROM t1, t2, t3, t4 GROUP BY a ORDER BY a", 16))
    .to_equal("SELECT a\nFROM t1,\n  t2,\n  t3,\n  t4\nGROUP BY a\nORDER BY a")
    soft
    .expect(
      pretty(
        "SELECT a FROM t LEFT JOIN uuuuuuuuuu AS u ON t.id = u.id AND t.kind = u.kind",
        40,
      ),
    )
    .to_equal(
      "SELECT a\nFROM t\n  LEFT JOIN uuuuuuuuuu AS u\n    ON t.id = u.id AND t.kind = u.kind",
    )
    soft
    .expect(
      pretty(
        "WITH xxxxxx AS (SELECT a FROM t), yyyyyy AS (SELECT b FROM u) SELECT * FROM xxxxxx",
        40,
      ),
    )
    .to_equal(
      "WITH\n  xxxxxx AS (SELECT a FROM t),\n  yyyyyy AS (SELECT b FROM u)\nSELECT *\nFROM xxxxxx",
    )
  })
}
