///|
fn sx(source : String, width? : Int = 1_000_000_000) -> String raise {
  @sexp.to_sexp(@parser.parse_statement(source), width~)
}

///|
test "flat S-expressions keep the test shape format" {
  @expect.expect_all(soft => {
    soft
    .expect(sx("SELECT a FROM t WHERE a > 1"))
    .to_equal("(select a (from t) (where (> a 1)))")
    soft
    .expect(sx("(g MATCH (a)-[e]->(b))"))
    .to_equal("(match g (path (node a) (edge -> [e]) (node b)))")
    soft.expect(sx("SEXP()")).to_equal("(sexp)")
    soft.expect(sx("ROW()")).to_equal("(row)")
    soft.expect(sx("{'a': 1}")).to_equal("{'a':1}")
  })
}

///|
test "wide trees break and indent by 2" {
  let text = sx(
    "SELECT aaaaaaaaaa, bbbbbbbbbb, cccccccccc FROM tttttttttt WHERE xxxxxxxxxx = 1",
    width=40,
  )
  @expect.expect(text).to_equal(
    "(select\n  aaaaaaaaaa,\n  bbbbbbbbbb,\n  cccccccccc\n  (from tttttttttt)\n  (where (= xxxxxxxxxx 1)))",
  )
}

///|
test "deep left chains do not overflow the stack" {
  let n = 1000
  @expect.expect_all(soft => {
    soft.expect(sx("a" + " AND a".repeat(n)).length() > 0).to_be_true()
    soft
    .expect(sx("SELECT 1" + " UNION SELECT 1".repeat(n)).length() > 0)
    .to_be_true()
    soft
    .expect(sx("SELECT * FROM t" + ", t".repeat(n)).length() > 0)
    .to_be_true()
    soft.expect(sx("1" + " + 1".repeat(n), width=80).length() > 0).to_be_true()
  })
}

///|
test "atoms escape quotes and control characters" {
  @expect.expect_all(soft => {
    soft
    .expect(sx("SELECT 'x)y', 'it''s', \"a\"\"b\" FROM t"))
    .to_equal("(select 'x)y', 'it''s', \"a\"\"b\" (from t))")
    soft
    .expect(sx("SELECT 'a\nb' FROM t"))
    .to_equal("(select 'a\\nb' (from t))")
    soft.expect(sx("a.'it''s'")).to_equal("(path a .'it''s')")
  })
}
