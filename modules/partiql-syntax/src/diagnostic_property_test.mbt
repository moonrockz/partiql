///|
let forbidden : Array[String] = [
  "`<<`", "`!=`", "`.`", "`[`", "`||`", "`<=`", "`>=`", "`<>`", "`=`", "IS", "IN",
  "LIKE", "BETWEEN", "OVERLAPS", "`/`", "`%`", "OR",
]

///|
test "law: render never aborts and marks the reported column" {
  @quickcheck.check(
    (s : SoupText) => {
      try {
        ignore(@syntax.parse(s.text))
        true
      } catch {
        Syntax(span~, expected~, ..) as e => {
          let text = @syntax.render(e, s.text, name="x")
          let at = @syntax.position(s.text, span.start)
          let lines = text.split("\n").map(v => v.to_owned()).collect()
          let location_ok = lines[1].has_suffix(":\{at.line}:\{at.column}") ||
            span.start >= s.text.length()
          let curated = !expected.iter().any(x => forbidden.contains(x))
          location_ok && curated
        }
        e => {
          ignore(@syntax.render(e, s.text, name="x"))
          true
        }
      }
    },
    count=1000,
  )
}

///|
test "root re-exports" {
  let statement = @syntax.parse("SELECT a FROM t")
  @expect.expect_all(soft => {
    soft.expect(@syntax.to_sexp(statement)).to_equal("(select a (from t))")
    soft.expect(@syntax.position("ab\ncd", 4)).to_equal({ line: 2, column: 2, })
  })
}
