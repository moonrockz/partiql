///|
test "text compares by code point, not by length" {
  @expect.expect_all(soft => {
    soft.expect(compare_text("b", "aa")).to_equal(1)
    soft.expect(compare_text("a", "aa")).to_equal(-1)
    soft.expect(compare_text("\u{10000}", "\u{FFFF}")).to_equal(1)
  })
}

///|
test "octets compare lexicographically" {
  @expect.expect_all(soft => {
    soft.expect(compare_octets(b"\x02", b"\x01\x01")).to_equal(1)
    soft.expect(compare_octets(b"\x01", b"\x01\x00")).to_equal(-1)
  })
}
