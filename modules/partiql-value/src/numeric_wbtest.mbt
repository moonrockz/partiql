///|
fn dec(coefficient : Int, exponent : Int) -> Num {
  num_of_decimal(
    @ion_core.Decimal::new(@bigint.BigInt::from_int(coefficient), exponent),
  )
}

///|
test "equal values of different kinds compare equal" {
  @expect.expect_all(soft => {
    soft.expect(compare_num(num_of_int64(1L), dec(10, -1))).to_equal(0)
    soft.expect(compare_num(num_of_int64(1L), num_of_double(1.0))).to_equal(0)
    soft.expect(compare_num(num_of_double(0.5), dec(5, -1))).to_equal(0)
    soft.expect(compare_num(num_of_double(-0.0), num_of_int64(0L))).to_equal(0)
  })
}

///|
test "doubles convert exactly" {
  @expect.expect_all(soft => {
    // 0.1 is not exactly representable: the double is slightly above 0.1.
    soft.expect(compare_num(num_of_double(0.1), dec(1, -1))).to_equal(1)
    // 2^53 + 1 is not a double; the nearest double is 2^53.
    soft
    .expect(
      compare_num(
        num_of_int64(9007199254740993L),
        num_of_double(9007199254740992.0),
      ),
    )
    .to_equal(1)
  })
}

///|
test "special doubles order" {
  let nan = num_of_double(@double.not_a_number)
  let neg_inf = num_of_double(@double.neg_infinity)
  let pos_inf = num_of_double(@double.infinity)
  @expect.expect_all(soft => {
    soft.expect(compare_num(nan, nan)).to_equal(0)
    soft.expect(compare_num(nan, neg_inf)).to_equal(-1)
    soft.expect(compare_num(neg_inf, num_of_int64(-1000000L))).to_equal(-1)
    soft.expect(compare_num(pos_inf, num_of_int64(1000000L))).to_equal(1)
  })
}

///|
test "huge exponents compare without scaling" {
  @expect.expect_all(soft => {
    soft.expect(compare_num(dec(1, 999999), dec(1, -999999))).to_equal(1)
    soft.expect(compare_num(dec(-1, 999999), dec(1, -999999))).to_equal(-1)
    soft.expect(compare_num(dec(10, 999998), dec(1, 999999))).to_equal(0)
  })
}

///|
test "negative values order" {
  @expect.expect_all(soft => {
    soft.expect(compare_num(num_of_int64(-2L), dec(-15, -1))).to_equal(-1)
    soft.expect(compare_num(dec(-15, -1), num_of_int64(-1L))).to_equal(-1)
  })
}

///|
test "sign_of is -1, 0 or 1 for any size" {
  @expect.expect_all(soft => {
    soft.expect(sign_of(10N.pow(52N))).to_equal(1)
    soft.expect(sign_of(-10N.pow(52N))).to_equal(-1)
    soft.expect(sign_of(0N)).to_equal(0)
  })
}
