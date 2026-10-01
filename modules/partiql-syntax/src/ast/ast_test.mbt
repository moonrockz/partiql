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
