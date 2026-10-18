///|
fn s(text : String) -> @value.Value {
  @value.Value::from_string(text)
}

///|
test "CHAR_LENGTH counts code points" {
  @expect.expect_all(soft => {
    soft.expect(char_length([s("")])).to_equal(@value.Value::from_int(0))
    soft
    .expect(char_length([s("français")]))
    .to_equal(@value.Value::from_int(8))
    soft
    .expect(char_length([s("😁😞😸😸")]))
    .to_equal(@value.Value::from_int(4))
    soft
    .expect(char_length([s("e\u{0301}")]))
    .to_equal(@value.Value::from_int(2))
    soft.expect(char_length([Null])).to_equal(Null)
    soft.expect(char_length([Missing])).to_equal(Missing)
    soft
    .expect(failure(() => char_length([@value.Value::from_int(1)])))
    .to_equal("type")
    soft
    .expect(failure(() => char_length([@value.Value::from_clob(b"ab")])))
    .to_equal("type")
  })
}

///|
test "OCTET_LENGTH and BIT_LENGTH count UTF-8 bytes" {
  @expect.expect_all(soft => {
    soft
    .expect(octet_length([s("français")]))
    .to_equal(@value.Value::from_int(9))
    soft.expect(octet_length([s("😁")])).to_equal(@value.Value::from_int(4))
    soft.expect(octet_length([s("話")])).to_equal(@value.Value::from_int(3))
    soft
    .expect(octet_length([@value.Value::from_blob(b"\x00\x01")]))
    .to_equal(@value.Value::from_int(2))
    soft
    .expect(octet_length([@value.Value::from_clob(b"abc")]))
    .to_equal(@value.Value::from_int(3))
    soft.expect(bit_length([s("abc")])).to_equal(@value.Value::from_int(24))
    soft
    .expect(bit_length([s("français")]))
    .to_equal(@value.Value::from_int(72))
    soft.expect(bit_length([Null])).to_equal(Null)
    soft
    .expect(failure(() => bit_length([@value.Value::from_int(1)])))
    .to_equal("type")
  })
}

///|
test "TRIM removes a set of code points" {
  @expect.expect_all(soft => {
    soft.expect(trim(Both, [s("  foobar  ")])).to_equal(s("foobar"))
    soft.expect(trim(Both, [s("\tfoobar\t")])).to_equal(s("\tfoobar\t"))
    soft.expect(trim(Both, [s("12"), s("111112a1212121211")])).to_equal(s("a"))
    soft
    .expect(trim(Leading, [s("12"), s("111112a1212121211")]))
    .to_equal(s("a1212121211"))
    soft
    .expect(trim(Trailing, [s("12"), s("111112a1212121211")]))
    .to_equal(s("111112a"))
    soft
    .expect(trim(Both, [s("👶🏻"), s("👶🏻👩👶🏻")]))
    .to_equal(s("👩"))
    soft.expect(trim(Both, [s(" "), s(" ")])).to_equal(s(""))
    soft.expect(trim(Both, [s(""), s("abc")])).to_equal(s("abc"))
    soft.expect(trim(Leading, [Null, Missing])).to_equal(Missing)
    soft.expect(trim(Leading, [s("x"), Null])).to_equal(Null)
    soft
    .expect(failure(() => trim(Both, [@value.Value::from_int(1), s("test")])))
    .to_equal("type")
  })
}

///|
test "SUBSTRING follows SQL-92 E = S + L over code points" {
  let digits = s("123456789")
  let fraction = @value.Value::from_decimal(@ion_core.Decimal::parse("1.1"))
  @expect.expect_all(soft => {
    soft.expect(substring([digits, @value.Value::from_int(0)])).to_equal(digits)
    soft
    .expect(substring([digits, @value.Value::from_int(-4)]))
    .to_equal(digits)
    soft.expect(substring([s(""), @value.Value::from_int(-1)])).to_equal(s(""))
    soft
    .expect(
      substring([digits, @value.Value::from_int(0), @value.Value::from_int(2)]),
    )
    .to_equal(s("1"))
    soft
    .expect(
      substring([digits, @value.Value::from_int(-4), @value.Value::from_int(6)]),
    )
    .to_equal(s("1"))
    soft
    .expect(
      substring([s("1"), @value.Value::from_int(-4), @value.Value::from_int(1)]),
    )
    .to_equal(s(""))
    soft
    .expect(
      substring([digits, @value.Value::from_int(1), @value.Value::from_int(0)]),
    )
    .to_equal(s(""))
    soft
    .expect(
      substring([digits, @value.Value::from_int(0), @value.Value::from_int(999)]),
    )
    .to_equal(digits)
    soft
    .expect(substring([s("😁😞😸😸"), @value.Value::from_int(3)]))
    .to_equal(s("😸😸"))
    soft
    .expect(substring([s("👩🏽"), @value.Value::from_int(2)]))
    .to_equal(s("🏽"))
    soft
    .expect(
      failure(() => {
        substring([
          s("1"),
          @value.Value::from_int(4),
          @value.Value::from_int(-11),
        ])
      }),
    )
    .to_equal("type")
    soft.expect(failure(() => substring([s(""), fraction]))).to_equal("type")
    soft.expect(substring([Null, Missing])).to_equal(Missing)
    soft
    .expect(substring([Null, @value.Value::from_int(1), Null]))
    .to_equal(Null)
    // Huge positions: no overflow. E = S + L in BigInt, so a minimum start
    // with a maximum length ends before position 1.
    soft
    .expect(
      substring([
        s("abc"),
        @value.Value::from_int(-9223372036854775808L),
        @value.Value::from_int(9223372036854775807L),
      ]),
    )
    .to_equal(s(""))
    soft
    .expect(
      substring([
        s("abc"),
        @value.Value::from_int(9223372036854775807L),
        @value.Value::from_int(9223372036854775807L),
      ]),
    )
    .to_equal(s(""))
    soft
    .expect(
      substring([
        s("abc"),
        @value.Value::from_int(-5L),
        @value.Value::from_int(9223372036854775807L),
      ]),
    )
    .to_equal(s("abc"))
  })
}

///|
test "POSITION and OVERLAY" {
  @expect.expect_all(soft => {
    soft
    .expect(position([s(""), s("abcdefg")]))
    .to_equal(@value.Value::from_int(1))
    soft.expect(position([s(""), s("")])).to_equal(@value.Value::from_int(1))
    soft
    .expect(position([s("cde"), s("abcdefg")]))
    .to_equal(@value.Value::from_int(3))
    soft
    .expect(position([s("ghi"), s("abcdefg")]))
    .to_equal(@value.Value::from_int(0))
    soft
    .expect(position([s("😸"), s("😁😸")]))
    .to_equal(@value.Value::from_int(2))
    soft.expect(position([Null, Missing])).to_equal(Missing)
    soft
    .expect(overlay([s("hello"), s(""), @value.Value::from_int(1)]))
    .to_equal(s("hello"))
    soft
    .expect(
      overlay([
        s("hello"),
        s(""),
        @value.Value::from_int(2),
        @value.Value::from_int(3),
      ]),
    )
    .to_equal(s("ho"))
    soft
    .expect(overlay([s("hello"), s("XX"), @value.Value::from_int(1)]))
    .to_equal(s("XXllo"))
    soft
    .expect(
      overlay([
        s("hello"),
        s("XX"),
        @value.Value::from_int(1),
        @value.Value::from_int(100),
      ]),
    )
    .to_equal(s("XX"))
    soft
    .expect(
      overlay([
        s("hello"),
        s("XX"),
        @value.Value::from_int(1),
        @value.Value::from_int(0),
      ]),
    )
    .to_equal(s("XXhello"))
    soft
    .expect(overlay([s("hello"), s("XX"), @value.Value::from_int(7)]))
    .to_equal(s("helloXX"))
    soft
    .expect(
      overlay([
        s("hello"),
        s("XX"),
        @value.Value::from_int(2),
        @value.Value::from_int(3),
      ]),
    )
    .to_equal(s("hXXo"))
    soft
    .expect(
      overlay([
        s("hello"),
        s("X"),
        @value.Value::from_int(2),
        @value.Value::from_int(-1),
      ]),
    )
    .to_equal(s("hXhello"))
    soft
    .expect(overlay([s(""), s("X"), @value.Value::from_int(1)]))
    .to_equal(s("X"))
    soft
    .expect(
      failure(() => overlay([s("hello"), s("X"), @value.Value::from_int(0)])),
    )
    .to_equal("type")
    soft
    .expect(failure(() => overlay([s("a"), s("X"), s("1")])))
    .to_equal("type")
  })
}

///|
test "TEXT_REPLACE" {
  @expect.expect_all(soft => {
    soft
    .expect(text_replace([s("abcdefabcdef"), s("cd"), s("XX")]))
    .to_equal(s("abXXefabXXef"))
    soft
    .expect(text_replace([s("abcabcabcdef"), s("abcabc"), s("XXX")]))
    .to_equal(s("XXXabcdef"))
    soft
    .expect(text_replace([s("abcabcabcdef"), s(""), s("X")]))
    .to_equal(s("XaXbXcXaXbXcXaXbXcXdXeXfX"))
    soft.expect(text_replace([s(""), s(""), s("XX")])).to_equal(s("XX"))
    soft.expect(text_replace([s(""), s("abc"), s("XX")])).to_equal(s(""))
    soft
    .expect(text_replace([s("😁😁"), s(""), s("-")]))
    .to_equal(s("-😁-😁-"))
    soft.expect(text_replace([Null, s("foo"), Missing])).to_equal(Missing)
  })
}
