///|
test "the flat renderer" {
  @expect.expect_all(soft => {
    soft.expect(render_flat(cat([Text("a"), Line, Text("b")]))).to_equal("a b")
    soft
    .expect(render_flat(cat([Text("a"), HardLine, Text("b")])))
    .to_equal("a\nb")
    soft
    .expect(render_flat(spaced([Text("x"), Nil, Text("y")])))
    .to_equal("x y")
    soft
    .expect(render_flat(sep([Text("1"), Text("2"), Text("3")], ", ")))
    .to_equal("1, 2, 3")
    soft.expect(render_flat(parens(Text("q")))).to_equal("(q)")
    soft.expect(render_flat(cat([]))).to_equal("")
  })
}

///|
test "the renderer handles very long documents" {
  let docs = Array::makei(200000, i => Text(if i % 2 == 0 { "a" } else { " " }))
  @expect.expect(render_flat(cat(docs)).length()).to_equal(200000)
}
