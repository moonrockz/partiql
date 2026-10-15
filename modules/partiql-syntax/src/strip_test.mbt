///|
test "statements that differ only in layout are equal after strip_spans" {
  let a = @syntax.parse("SELECT a, b FROM t WHERE x = 1")
  let b = @syntax.parse("select  a ,b\nfrom t   where x=1")
  let c = @syntax.parse("SELECT a, b FROM t WHERE x = 2")
  @expect.expect_all(soft => {
    soft.expect(a == b).to_be_false()
    soft.expect(a.strip_spans()).to_equal(b.strip_spans())
    soft.expect(a.strip_spans() == c.strip_spans()).to_be_false()
  })
}

///|
test "strip_spans reaches graph patterns and FROM items" {
  let a = @syntax.parse(
    "SELECT * FROM (g MATCH (x:L WHERE x.a = 1) -[e]->{1,2} (y))",
  )
  let b = @syntax.parse(
    "SELECT *  FROM ( g  MATCH (x : L WHERE x.a=1)-[ e ]->{1,2}(y) )",
  )
  @expect.expect(a.strip_spans()).to_equal(b.strip_spans())
}

///|
fn parse_expr(source : String) -> @ast.Expr raise {
  guard @syntax.parse(source) is Query({ body: Expr(e), .. }) else {
    fail("not an expression: \{source}")
  }
  e
}

///|
test "canonical ignores spans and the case of regular identifiers" {
  let a = parse_expr("T.a + 1")
  let b = parse_expr("t.A  +  1")
  let quoted = parse_expr("\"T\".a + 1")
  @expect.expect_all(soft => {
    soft.expect(a.canonical()).to_equal(b.canonical())
    soft.expect(a.canonical() == quoted.canonical()).to_be_false()
    soft.expect(a.canonical().canonical()).to_equal(a.canonical())
    // strip_spans keeps the case.
    soft.expect(a.strip_spans() == b.strip_spans()).to_be_false()
  })
}
