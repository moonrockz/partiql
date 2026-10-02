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

///|
test "format prints long left-associative chains without deep recursion" {
  let n = 1000
  @expect.expect_all(soft => {
    soft
    .expect(@syntax.format("select a from t where a" + " and a = 1".repeat(n)))
    .to_equal("SELECT a FROM t WHERE a" + " AND a = 1".repeat(n) + ";\n")
    soft
    .expect(@syntax.format("1" + " + 1".repeat(n)))
    .to_equal("1" + " + 1".repeat(n) + ";\n")
    soft
    .expect(@syntax.format("a" + " is null".repeat(n)))
    .to_equal("a" + " IS NULL".repeat(n) + ";\n")
    soft
    .expect(@syntax.format("select 1" + " union select 1".repeat(n)))
    .to_equal("SELECT 1" + " UNION SELECT 1".repeat(n) + ";\n")
    soft
    .expect(@syntax.format("select * from t" + ", t".repeat(n)))
    .to_equal("SELECT * FROM t" + ", t".repeat(n) + ";\n")
    soft
    .expect(@syntax.format("select * from t" + " cross join t".repeat(n)))
    .to_equal("SELECT * FROM t" + " CROSS JOIN t".repeat(n) + ";\n")
  })
}

///|
test "pretty scripts: blank lines and comments" {
  let commented = "select a, -- first\n b from t"
  @expect.expect_all(soft => {
    soft
    .expect(
      @syntax.format(
        "select 1; select a, b, c from t where x = 1 and y = 2; select 2",
        width=30,
      ),
    )
    .to_equal(
      "SELECT 1;\n\nSELECT a, b, c\nFROM t\nWHERE x = 1 AND y = 2;\n\nSELECT 2;\n",
    )
    soft
    .expect(@syntax.format("select 1; select 2", width=30))
    .to_equal("SELECT 1;\nSELECT 2;\n")
    soft
    .expect(@syntax.format(commented, width=80))
    .to_equal("SELECT\n  a,\n  -- first\n  b\nFROM t;\n")
    soft
    .expect(
      @syntax.format("select a from t where x = 1 -- why\n and y = 2", width=80),
    )
    .to_equal("SELECT a\nFROM t\nWHERE x = 1\n  AND -- why\n  y = 2;\n")
    soft
    .expect(@syntax.format("-- top\nselect 1; -- end", width=80))
    .to_equal("-- top\nSELECT 1;\n-- end\n")
    let once = @syntax.format(commented, width=20)
    soft.expect(@syntax.format(once, width=20)).to_equal(once)
  })
}
