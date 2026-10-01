///|
fn span(start : Int, end : Int) -> @ast.Span {
  { start, end, }
}

///|
test "line_column counts lines and UTF-16 columns from 1" {
  let source = "ab\ncd\r\nef\u{1F600}g"
  @expect.expect_all(soft => {
    soft.expect(span(0, 1).line_column(source)).to_equal(((1, 1), (1, 2)))
    soft.expect(span(3, 5).line_column(source)).to_equal(((2, 1), (2, 3)))
    // After "\r\n", line 3 starts at offset 7; the emoji is 2 code units.
    soft.expect(span(9, 12).line_column(source)).to_equal(((3, 3), (3, 6)))
  })
}

///|
test "merge covers both spans" {
  @expect.expect(span(4, 6).merge(span(1, 5))).to_equal(span(1, 6))
}

///|
test "graph nodes compare structurally" {
  let name : @ast.Identifier = {
    text: "L",
    delimited: false,
    span: span(3, 4),
  }
  let label : @ast.Label = { kind: Name(name), span: span(3, 4), }
  let node : @ast.PathPart = Node({
    variable: None,
    label: Some(label),
    where_: None,
    span: span(1, 5),
  })
  let edge : @ast.PathPart = Edge({
    direction: Right,
    filler: None,
    quantifier: Some({ kind: Range(lower=1, upper=None), span: span(7, 11), }),
    span: span(5, 11),
  })
  @expect.expect_all(soft => {
    soft.expect(node).to_equal(node)
    soft.expect(node == edge).to_be_false()
  })
}
