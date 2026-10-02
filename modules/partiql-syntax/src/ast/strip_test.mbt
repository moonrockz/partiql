///|
test "strip_spans zeroes every span and keeps the structure" {
  let a : @ast.Identifier = {
    text: "a",
    delimited: false,
    span: { start: 7, end: 8, },
  }
  let e : @ast.Expr = {
    kind: Binary(
      Add,
      { kind: VarRef(a, qualified=false), span: { start: 7, end: 8, }, },
      { kind: Lit(Int("1")), span: { start: 11, end: 12, }, },
    ),
    span: { start: 7, end: 12, },
  }
  let zero : @ast.Span = { start: 0, end: 0, }
  let stripped = e.strip_spans()
  @expect.expect_all(soft => {
    soft.expect(stripped.span).to_equal(zero)
    guard stripped.kind is Binary(Add, left, right) else {
      fail("shape changed")
    }
    soft.expect(left.span).to_equal(zero)
    soft.expect(right.span).to_equal(zero)
    soft
    .expect(left.kind is VarRef({ span, .. }, ..) && span == zero)
    .to_be_true()
    soft.expect(stripped.strip_spans()).to_equal(stripped)
  })
}
