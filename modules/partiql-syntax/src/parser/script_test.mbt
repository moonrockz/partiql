///|
fn script_shapes(source : String) -> Array[String] raise {
  @parser.parse_script(source).statements.map(s => {
    match s {
      Query(q) => query_shape(q)
    }
  })
}

///|
test "parse_script splits statements on semicolons" {
  @expect.expect_all(soft => {
    soft
    .expect(script_shapes("SELECT a FROM t; SELECT b FROM u;"))
    .to_equal(["(select a (from t))", "(select b (from u))"])
    soft.expect(script_shapes("SELECT 1")).to_equal(["(select 1)"])
    soft
    .expect(script_shapes(";;SELECT 1;;;SELECT 2"))
    .to_equal(["(select 1)", "(select 2)"])
    soft.expect(script_shapes("")).to_equal([])
    soft.expect(script_shapes("  \n ")).to_equal([])
    soft.expect(script_shapes(";;")).to_equal([])
    soft
    .expect(script_shapes("-- only a comment\n/* and another */"))
    .to_equal([])
  })
}

///|
test "parse_script keeps the comments" {
  let script = @parser.parse_script("-- a\nSELECT 1; /* b */ SELECT 2 -- c")
  @expect.expect(script.comments.map(c => c.text)).to_equal([
    "-- a", "/* b */", "-- c",
  ])
}

///|
test "parse_script stops at the first error" {
  @expect.expect_all(soft => {
    soft
    .expect_call(() => @parser.parse_script("SELECT 1; SELECT FROM; SELECT 3"))
    .to_raise_matching(syntax_error, description="Syntax")
    soft
    .expect_call(() => @parser.parse_script("SELECT 1 SELECT 2"))
    .to_raise_matching(syntax_error, description="Syntax")
  })
}
