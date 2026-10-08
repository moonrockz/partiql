///|
fn dec(text : String) -> @ion_core.Decimal {
  parse_decimal(text).unwrap()
}

///|
/// A decimal as a value, which compares exponent and coefficient.
fn w(d : @ion_core.Decimal) -> @value.Value {
  Decimal(d)
}

///|
test "round_decimal rounds half even to 38 digits, also when negative" {
  @expect.expect_all(soft => {
    soft
    .expect(w(round_decimal(dec("-0.123456789012345678901234567890123456785"))))
    .to_equal(w(dec("-0.12345678901234567890123456789012345678")))
    soft
    .expect(w(round_decimal(dec("-0.123456789012345678901234567890123456786"))))
    .to_equal(w(dec("-0.12345678901234567890123456789012345679")))
    soft
    .expect(w(round_decimal(dec("-99999999999999999999999999999999999999.9"))))
    .to_equal(w(dec("-10000000000000000000000000000000000000d1")))
    soft.expect(w(round_decimal(dec("-1.5")))).to_equal(w(dec("-1.5")))
  })
}

///|
test "decimal division keeps the natural scale of an exact quotient" {
  @expect.expect_all(soft => {
    soft.expect(w(decimal_div(dec("-7.5"), dec("2.5")))).to_equal(w(dec("-3")))
    soft.expect(w(decimal_div(dec("1"), dec("8")))).to_equal(w(dec("0.125")))
    soft
    .expect(w(decimal_div(dec("-1"), dec("3"))))
    .to_equal(w(dec("-0.33333333333333333333333333333333333333")))
    soft.expect(w(decimal_div(dec("0.00"), dec("3")))).to_equal(w(dec("0.00")))
  })
}

///|
test "parse_decimal reads an exponent" {
  @expect.expect_all(soft => {
    soft.expect(parse_decimal("1e0").map(w)).to_equal(Some(w(dec("1"))))
    soft.expect(parse_decimal("2.25E-1").map(w)).to_equal(Some(w(dec("0.225"))))
    soft.expect(parse_decimal("1e+2").map(w)).to_equal(Some(w(dec("1d2"))))
    soft.expect(parse_decimal("e").map(w)).to_equal(None)
  })
}
