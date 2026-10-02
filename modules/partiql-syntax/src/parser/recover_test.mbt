///|
fn recovered(source : String) -> (Array[String], Array[String]) {
  let r = @parser.parse_script_recovering(source)
  (
    r.script.statements.map(s => @sexp.to_sexp(s, width=flat)),
    r.errors.map(e => {
      match e {
        Syntax(message~, ..) | Unsupported(message~, ..) => message
      }
    }),
  )
}

///|
fn sx(source : String) -> String raise {
  @sexp.to_sexp(@parser.parse_statement(source), width=flat)
}

///|
test "statement-level recovery" {
  @expect.expect_all(soft => {
    soft
    .expect(recovered("SELECT a FROM t; SELECT FROM WHERE; SELECT b FROM u"))
    .to_equal(
      (
        [
          sx("SELECT a FROM t"),
          "(select (error) (from (error)) (where (error)))",
          sx("SELECT b FROM u"),
        ],
        [
          "expected an expression", "expected an expression", "expected an expression",
        ],
      ),
    )
    let unsupported = recovered("SELECT 1; INSERT INTO t VALUES (1); SELECT 2")
    soft
    .expect(unsupported.1)
    .to_equal(["INSERT statements are not supported yet"])
    soft.expect(unsupported.0.length()).to_equal(3)
    soft.expect(recovered("SELECT (a FROM t; SELECT 2").0.length()).to_equal(2)
    soft.expect(recovered(") ) SELECT 1").1.length() >= 1).to_be_true()
    soft.expect(recovered("SELECT a FROM t").1).to_equal([])
    soft
    .expect(recovered("SELECT a § FROM t").1)
    .to_equal(["unexpected character `§`"])
    soft.expect(recovered(";;").0).to_equal([])
    let deep = "SELECT " +
      "(".repeat(200) +
      "1" +
      ")".repeat(200) +
      "; SELECT 2"
    soft.expect(recovered(deep).1).to_equal(["nesting is too deep"])
    soft.expect(recovered(deep).0.length()).to_equal(2)
    let many = Array::make(150, "SELECT FROM").join("; ")
    soft.expect(recovered(many).1.length()).to_equal(100)
    soft.expect(recovered("SELECT 1 2; SELECT 3").0.length()).to_equal(2)
  })
}

///|
test "valid input gives the strict tree and no errors" {
  @expect.expect_all(soft => {
    for
      source in [
        "SELECT a, b FROM t WHERE x = 1", "SELECT * FROM (a JOIN b ON x), c", "(g MATCH (a)-[e]->(b)); VALUES (1, 2)",
        "SELECT f(DISTINCT x) FROM t GROUP BY x ORDER BY x LIMIT 1", "-- c\nSELECT 1; /* d */",
      ] {
      let r = @parser.parse_script_recovering(source)
      soft
      .expect(r)
      .to_equal({ script: @parser.parse_script(source), errors: [], })
    }
  })
}

///|
test "clause and list-item recovery" {
  @expect.expect_all(soft => {
    let (trees, errors) = recovered("SELECT a, , b FROM t")
    soft.expect(errors).to_equal(["expected an expression"])
    soft.expect(trees[0]).to_equal("(select a, (error), b (from t))")
    let (trees, errors) = recovered("SELECT a FROM t WHERE x = = 1 GROUP BY y")
    soft.expect(errors).to_equal(["expected an expression"])
    soft
    .expect(trees[0])
    .to_equal("(select a (from t) (where (error)) (group y))")
    let (trees, errors) = recovered("SELECT f(a, b FROM t")
    soft.expect(errors).to_equal(["expected `,` or `)`"])
    soft.expect(trees[0]).to_equal("(select (call f a b) (from t))")
    let (_, errors) = recovered("SELECT f(a b) FROM t")
    soft.expect(errors.length()).to_equal(1)
    let (trees, errors) = recovered("SELECT [1, `{a:`, 3] FROM t")
    soft.expect(errors.length()).to_equal(1)
    soft.expect(trees[0]).to_equal("(select [1 (error) 3] (from t))")
    let (trees, errors) = recovered("SELECT `{a: }` FROM t WHERE x = `[1,`")
    soft.expect(errors.length()).to_equal(2)
    soft
    .expect(trees[0])
    .to_equal("(select (error) (from t) (where (= x (error))))")
    let (trees, errors) = recovered("SELECT * FROM (a JOIN b ON) , c WHERE x")
    soft.expect(errors.length()).to_equal(1)
    soft.expect(trees[0]).to_contain("(where x)")
    let (_, errors) = recovered(
      "SELECT a FROM t WHERE ; SELECT b FROM u WHERE ;",
    )
    soft
    .expect(errors)
    .to_equal(["expected an expression", "expected an expression"])
    let (_, errors) = recovered("SELECT {'a': 1, 'b' 2} FROM t")
    soft.expect(errors).to_equal(["expected `:`"])
    let (_, errors) = recovered("SELECT <<1, 2 FROM t")
    soft.expect(errors).to_equal(["expected `,` or `>>`"])
    let (trees, errors) = recovered("VALUES (1, 2), (3 4), (5, 6)")
    soft.expect(errors.length()).to_equal(1)
    soft.expect(trees[0]).to_contain("(row 5 6)")
    let (trees, errors) = recovered("SELECT a FROM t ORDER BY a, LIMIT 1")
    soft.expect(errors.length()).to_equal(1)
    soft.expect(trees[0]).to_contain("(limit 1)")
  })
}

///|
test "the first error is the strict error" {
  @expect.expect_all(soft => {
    for
      source in [
        "SELECT a, , b FROM t", "SELECT f(a, b FROM t", "SELECT a FROM t WHERE x = = 1",
        "SELECT * FROM (a JOIN b ON) , c", "SELECT {'a': 1, 'b' 2} FROM t", "SELECT <<1, 2 FROM t",
        "VALUES (1, 2), (3 4)",
      ] {
      let strict = try @parser.parse_script(source) catch {
        e => Some(e)
      } noraise {
        _ => None
      }
      soft
      .expect(@parser.parse_script_recovering(source).errors.get(0))
      .to_equal(strict)
    }
  })
}
