///|
test "format: statements, comments and layout" {
  @expect.expect_all(soft => {
    soft
    .expect(@syntax.format("select a from t"))
    .to_equal("SELECT a FROM t;\n")
    soft
    .expect(@syntax.format("select 1; select 2;"))
    .to_equal("SELECT 1;\nSELECT 2;\n")
    soft.expect(@syntax.format("")).to_equal("")
    soft.expect(@syntax.format(" ;; \n")).to_equal("")
    soft.expect(@syntax.format("-- only\n")).to_equal("-- only\n")
    soft
    .expect(@syntax.format("-- head\nselect a /* inline */ from t -- tail"))
    .to_equal("-- head\nSELECT a FROM /* inline */ t;\n-- tail\n")
    soft
    .expect(@syntax.format("select a from t order /* x */ by a"))
    .to_equal("SELECT a FROM t ORDER BY /* x */ a;\n")
    soft
    .expect(@syntax.format("select a -- why\n from t"))
    .to_equal("SELECT a FROM -- why\nt;\n")
    soft
    .expect(@syntax.format("select 1 -- one\r\n; select 2 -- two"))
    .to_equal("SELECT 1;\n-- one\nSELECT 2;\n-- two\n")
    soft
    .expect(@syntax.format("select 'héllo', \"日本\" /* 🎉 */ from t"))
    .to_equal("SELECT 'héllo', \"日本\" FROM /* 🎉 */ t;\n")
    soft
    .expect(@syntax.format("select - /* c */ 1"))
    .to_equal("SELECT - /* c */ 1;\n")
    soft
    .expect(@syntax.format("select - -- c\n 1"))
    .to_equal("SELECT - -- c\n1;\n")
  })
}

///|
fn same_tree(source : String) -> Bool raise {
  let formatted = @syntax.format(source)
  @syntax.parse_script(formatted).strip_spans().statements ==
  @syntax.parse_script(source).strip_spans().statements &&
  @syntax.format(formatted) == formatted
}

///|
test "format keeps the tree and is idempotent" {
  @expect.expect_all(soft => {
    for
      source in [
        "select a, b from t where x between 1 and 2 -- c\n order by a",
        "(g MATCH (a) -[e]-> (b) WHERE a.x = 1); select 1",
        "/* a */ select /* b */ a /* c */ from /* d */ t /* e */",
        "(" + "(".repeat(94) + "1" + ")".repeat(94) + ")",
        "(SELECT VALUE ".repeat(45) + "1" + ")".repeat(45),
      ] {
      soft
      .expect_call(
        () => same_tree(source),
        label=source.view(end_offset=24).to_owned(),
      )
      .to_return()
      .to_be_true()
    }
  })
}
