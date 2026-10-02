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

///|
test "groups, nests and soft lines" {
  let doc = Group(
    cat([
      Text("f("),
      Nest(2, cat([SoftLine, Text("a,"), Line, Text("b")])),
      SoftLine,
      Text(")"),
    ]),
  )
  @expect.expect_all(soft => {
    soft.expect(render_flat(doc)).to_equal("f(a, b)")
    soft.expect(render(doc, 80)).to_equal("f(a, b)")
    soft.expect(render(doc, 4)).to_equal("f(\n  a,\n  b\n)")
    soft
    .expect(render_flat(spaced([Text("x"), Nil, Text("y")])))
    .to_equal("x y")
    soft.expect(render(spaced([Text("x"), Text("y")]), 1)).to_equal("x y")
    soft
    .expect(render(Group(lines([Text("x"), Nil, Text("y")])), 1))
    .to_equal("x\ny")
    soft
    .expect(render(Group(lines([Text("x"), Text("y")])), 0))
    .to_equal("x\ny")
  })
}

///|
test "converting a very long document does not overflow" {
  let docs = Array::makei(100000, _ => Text("a"))
  @expect.expect(render(cat(docs), 80).length()).to_equal(100000)
}
