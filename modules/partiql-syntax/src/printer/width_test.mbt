///|
test "a width keeps short statements on one line" {
  let s = @parser.parse_statement("select a, b from t where x = 1")
  let script = @parser.parse_script("select 1; select 2")
  @expect.expect_all(soft => {
    soft.expect(@printer.print(s)).to_equal("SELECT a, b FROM t WHERE x = 1")
    soft
    .expect(@printer.print(s, width=80))
    .to_equal("SELECT a, b FROM t WHERE x = 1")
    soft
    .expect(@printer.print_script(script, width=80))
    .to_equal("SELECT 1;\nSELECT 2;\n")
  })
}
