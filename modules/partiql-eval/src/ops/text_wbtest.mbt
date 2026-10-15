///|
fn s(text : String) -> @value.Value {
  String(text)
}

///|
test "CHAR_LENGTH counts code points" {
  @expect.expect_all(soft => {
    soft.expect(char_length([s("")])).to_equal(Int(0))
    soft.expect(char_length([s("français")])).to_equal(Int(8))
    soft.expect(char_length([s("😁😞😸😸")])).to_equal(Int(4))
    soft.expect(char_length([s("e\u{0301}")])).to_equal(Int(2))
    soft.expect(char_length([Null])).to_equal(Null)
    soft.expect(char_length([Missing])).to_equal(Missing)
    soft.expect(failure(() => char_length([Int(1)]))).to_equal("type")
    soft.expect(failure(() => char_length([Clob(b"ab")]))).to_equal("type")
  })
}

///|
test "OCTET_LENGTH and BIT_LENGTH count UTF-8 bytes" {
  @expect.expect_all(soft => {
    soft.expect(octet_length([s("français")])).to_equal(Int(9))
    soft.expect(octet_length([s("😁")])).to_equal(Int(4))
    soft.expect(octet_length([s("話")])).to_equal(Int(3))
    soft.expect(octet_length([Blob(b"\x00\x01")])).to_equal(Int(2))
    soft.expect(octet_length([Clob(b"abc")])).to_equal(Int(3))
    soft.expect(bit_length([s("abc")])).to_equal(Int(24))
    soft.expect(bit_length([s("français")])).to_equal(Int(72))
    soft.expect(bit_length([Null])).to_equal(Null)
    soft.expect(failure(() => bit_length([Int(1)]))).to_equal("type")
  })
}
