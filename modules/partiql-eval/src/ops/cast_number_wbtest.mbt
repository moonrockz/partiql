///|
/// A decimal value for use inside a `failure` closure, which may raise only
/// `OpFailure`.
fn dn(text : String) -> @value.Value {
  try @value.Value::from_decimal(@ion_core.Decimal::parse(text)) catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
let int8 : CastTarget = Integer(Bits8)

///|
let int32 : CastTarget = Integer(Bits32)

///|
let int64 : CastTarget = Integer(Bits64)

///|
test "cast: NULL, MISSING and ANY" {
  @expect.expect_all(soft => {
    soft.expect(cast(Null, int32)).to_equal(Null)
    soft.expect(cast(Missing, Bool)).to_equal(Missing)
    soft.expect(cast(Null, Text(String))).to_equal(Null)
    soft
    .expect(cast(@value.Value::from_int(1), Any))
    .to_equal(@value.Value::from_int(1))
    soft
    .expect(cast(@value.Value::from_string("a"), Any))
    .to_equal(@value.Value::from_string("a"))
    let boxed_null = @value.Value::from_ion(@ion_core.IonValue::typed_null(Int))
    soft.expect(cast(boxed_null, int32)).to_equal(Null)
  })
}

///|
test "cast to BOOL" {
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_bool(true), Bool))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(cast(@value.Value::from_int(0), Bool))
    .to_equal(@value.Value::from_bool(false))
    soft
    .expect(cast(@value.Value::from_int(-3), Bool))
    .to_equal(@value.Value::from_bool(true))
    soft.expect(cast(d("0.00"), Bool)).to_equal(@value.Value::from_bool(false))
    soft.expect(cast(d("-0.0"), Bool)).to_equal(@value.Value::from_bool(false))
    soft.expect(cast(d("0.01"), Bool)).to_equal(@value.Value::from_bool(true))
    soft
    .expect(cast(@value.Value::from_float(-0.0), Bool))
    .to_equal(@value.Value::from_bool(false))
    soft
    .expect(cast(@value.Value::from_float(2.5), Bool))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(failure(() => cast(@value.Value::from_float(0.0 / 0.0), Bool)))
    .to_equal("type")
    soft
    .expect(cast(@value.Value::from_string(" TrUe "), Bool))
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(cast(@value.Value::from_string("false"), Bool))
    .to_equal(@value.Value::from_bool(false))
    soft
    .expect(cast(@value.Value::from_string(" unknown "), Bool))
    .to_equal(Null)
    soft
    .expect(failure(() => cast(@value.Value::from_string("yes"), Bool)))
    .to_equal("type")
    soft
    .expect(failure(() => cast(@value.Value::from_string("1"), Bool)))
    .to_equal("type")
    soft
    .expect(failure(() => cast(@value.Value::from_list([]), Bool)))
    .to_equal("type")
  })
}

///|
test "cast to integers: ranges" {
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_int(-128), int8))
    .to_equal(@value.Value::from_int(-128))
    soft
    .expect(cast(@value.Value::from_int(127), int8))
    .to_equal(@value.Value::from_int(127))
    soft
    .expect(failure(() => cast(@value.Value::from_int(128), int8)))
    .to_equal("data")
    soft
    .expect(failure(() => cast(@value.Value::from_int(-129), int8)))
    .to_equal("data")
    soft
    .expect(cast(@value.Value::from_int(32767), Integer(Bits16)))
    .to_equal(@value.Value::from_int(32767))
    soft
    .expect(failure(() => cast(@value.Value::from_int(32768), Integer(Bits16))))
    .to_equal("data")
    soft
    .expect(cast(@value.Value::from_int(2147483647), int32))
    .to_equal(@value.Value::from_int(2147483647))
    soft
    .expect(failure(() => cast(@value.Value::from_int(2147483648), int32)))
    .to_equal("data")
    soft
    .expect(failure(() => cast(@value.Value::from_int(-2147483649), int32)))
    .to_equal("data")
    soft
    .expect(cast(@value.Value::from_int(-9223372036854775808L), int64))
    .to_equal(@value.Value::from_int(-9223372036854775808L))
    let big = @bigint.BigInt::from_string("9223372036854775808")
    soft
    .expect(failure(() => cast(@value.Value::from_bigint(big), int64)))
    .to_equal("data")
    soft
    .expect(cast(@value.Value::from_bool(true), int32))
    .to_equal(@value.Value::from_int(1))
    soft
    .expect(cast(@value.Value::from_bool(false), int8))
    .to_equal(@value.Value::from_int(0))
  })
}

///|
test "cast to integers: rounding half to even" {
  @expect.expect_all(soft => {
    soft.expect(cast(d("1.5"), int32)).to_equal(@value.Value::from_int(2))
    soft.expect(cast(d("2.5"), int32)).to_equal(@value.Value::from_int(2))
    soft.expect(cast(d("-2.5"), int32)).to_equal(@value.Value::from_int(-2))
    soft.expect(cast(d("0.5"), int32)).to_equal(@value.Value::from_int(0))
    soft.expect(cast(d("-1.5"), int32)).to_equal(@value.Value::from_int(-2))
    soft.expect(cast(d("2.5000001"), int32)).to_equal(@value.Value::from_int(3))
    soft.expect(cast(d("1d3"), int32)).to_equal(@value.Value::from_int(1000))
    soft
    .expect(cast(d("1d-2000000000"), int32))
    .to_equal(@value.Value::from_int(0))
    soft.expect(failure(() => cast(dn("1d2147483647"), int64))).to_equal("data")
    soft
    .expect(cast(@value.Value::from_float(1.5), int32))
    .to_equal(@value.Value::from_int(2))
    soft
    .expect(cast(@value.Value::from_float(-0.5), int32))
    .to_equal(@value.Value::from_int(0))
    soft
    .expect(failure(() => cast(@value.Value::from_float(1.0 / 0.0), int32)))
    .to_equal("data")
    soft
    .expect(failure(() => cast(@value.Value::from_float(0.0 / 0.0), int32)))
    .to_equal("data")
    soft
    .expect(failure(() => cast(@value.Value::from_float(1.0e19), int64)))
    .to_equal("data")
    let ion_float = @value.Value::from_ion(@ion_core.IonValue::float(1.5))
    soft.expect(cast(ion_float, int32)).to_equal(@value.Value::from_int(2))
  })
}

///|
test "cast to integers: text" {
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_string("12"), int32))
    .to_equal(@value.Value::from_int(12))
    soft
    .expect(cast(@value.Value::from_string(" -0b010 "), int32))
    .to_equal(@value.Value::from_int(-2))
    soft
    .expect(cast(@value.Value::from_string("0xA"), int32))
    .to_equal(@value.Value::from_int(10))
    soft
    .expect(cast(@value.Value::from_string("1.5"), int32))
    .to_equal(@value.Value::from_int(2))
    soft
    .expect(cast(@value.Value::from_string("2e1"), int32))
    .to_equal(@value.Value::from_int(20))
    soft
    .expect(failure(() => cast(@value.Value::from_string("2e10"), int32)))
    .to_equal("data")
    soft
    .expect(
      failure(() => {
        cast(@value.Value::from_string("92233720368547758070"), int64)
      }),
    )
    .to_equal("data")
    soft
    .expect(failure(() => cast(@value.Value::from_string("00xA"), int32)))
    .to_equal("type")
    soft
    .expect(failure(() => cast(@value.Value::from_string("hello"), int32)))
    .to_equal("type")
    soft
    .expect(failure(() => cast(@value.Value::from_clob(b"1"), int32)))
    .to_equal("type")
    soft
    .expect(
      failure(() => {
        cast(@value.Value::from_list([@value.Value::from_int(1)]), int32)
      }),
    )
    .to_equal("type")
    let ym = @value.Value::from_interval_ym(@value.IntervalYM(3L))
    soft.expect(failure(() => cast(ym, int32))).to_equal("unsupported")
  })
}

///|
test "cast to DECIMAL" {
  let fixed = (p : Int32, s : Int32) => {
    CastTarget::Decimal(Fixed(precision=p, scale=s))
  }
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_int(5), Decimal(Unconstrained)))
    .to_equal(d("5"))
    soft.expect(cast(d("1.50"), Decimal(Unconstrained))).to_equal(d("1.50"))
    soft
    .expect(
      cast(
        d("1.234567890123456789012345678901234567891"),
        Decimal(Unconstrained),
      ),
    )
    .to_equal(d("1.2345678901234567890123456789012345679"))
    soft
    .expect(cast(@value.Value::from_float(0.1), Decimal(Unconstrained)))
    .to_equal(d("0.1"))
    soft
    .expect(
      failure(() => {
        cast(@value.Value::from_float(0.0 / 0.0), Decimal(Unconstrained))
      }),
    )
    .to_equal("data")
    soft
    .expect(cast(@value.Value::from_bool(true), Decimal(Unconstrained)))
    .to_equal(d("1"))
    soft.expect(cast(d("99.94"), fixed(3, 1))).to_equal(d("99.9"))
    soft.expect(failure(() => cast(dn("99.95"), fixed(3, 1)))).to_equal("data")
    soft.expect(cast(d("0.125"), fixed(3, 2))).to_equal(d("0.12"))
    soft.expect(cast(d("0.135"), fixed(3, 2))).to_equal(d("0.14"))
    soft
    .expect(cast(@value.Value::from_int(5), fixed(5, 2)))
    .to_equal(d("5.00"))
    soft.expect(cast(@value.Value::from_int(12), fixed(2, 0))).to_equal(d("12"))
    soft
    .expect(failure(() => cast(@value.Value::from_int(123), fixed(2, 0))))
    .to_equal("data")
    soft.expect(cast(d("0d5"), fixed(1, 0))).to_equal(d("0"))
    soft.expect(cast(d("1d-2000000000"), fixed(5, 2))).to_equal(d("0.00"))
    soft
    .expect(failure(() => cast(dn("1d2000000000"), fixed(5, 2))))
    .to_equal("data")
    soft
    .expect(cast(@value.Value::from_string(" 1.005 "), fixed(4, 2)))
    .to_equal(d("1.00"))
    soft
    .expect(failure(() => cast(@value.Value::from_string("x"), fixed(4, 2))))
    .to_equal("type")
  })
}

///|
test "cast to REAL and DOUBLE PRECISION" {
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_int(3), Float(Double)))
    .to_equal(@value.Value::from_float(3.0))
    soft
    .expect(cast(d("0.1"), Float(Double)))
    .to_equal(@value.Value::from_float(0.1))
    soft
    .expect(cast(@value.Value::from_string("1.5e0"), Float(Double)))
    .to_equal(@value.Value::from_float(1.5))
    soft
    .expect(cast(@value.Value::from_bool(true), Float(Real)))
    .to_equal(@value.Value::from_float(1.0))
    soft
    .expect(cast(d("0.1"), Float(Real)))
    .to_equal(@value.Value::from_float(Float::from_double(0.1).to_double()))
    soft
    .expect(failure(() => cast(@value.Value::from_float(3.5e38), Float(Real))))
    .to_equal("data")
    soft.expect(failure(() => cast(dn("3.5d38"), Float(Real)))).to_equal("data")
    soft
    .expect(failure(() => cast(dn("1d400"), Float(Double))))
    .to_equal("data")
    soft
    .expect(cast(d("1d-50"), Float(Real)))
    .to_equal(@value.Value::from_float(0.0))
    soft
    .expect(cast(@value.Value::from_float(1.0 / 0.0), Float(Real)))
    .to_equal(@value.Value::from_float(1.0 / 0.0))
    soft
    .expect(cast(@value.Value::from_string("-inf"), Float(Double)))
    .to_equal(@value.Value::from_float(-1.0 / 0.0))
    let day = @value.Value::from_date(@value.Date(year=2020, month=1, day=1))
    soft.expect(failure(() => cast(day, Float(Double)))).to_equal("type")
  })
}

///|
test "cast to REAL rounds once from an exact value" {
  // 1 + 2^-24 is halfway between the binary32 values 1 and 1 + 2^-23. The
  // decimal just above it must round up; rounding through binary64 first
  // gives exactly the halfway value, which then rounds to even (down).
  let halfway = "1.000000059604644775390625"
  let above = halfway + "000000000000000000001"
  let one_up = Float::from_double(1.0 + 1.0 / 8388608.0).to_double()
  @expect.expect_all(soft => {
    soft
    .expect(cast(d(halfway), Float(Real)))
    .to_equal(@value.Value::from_float(1.0))
    soft
    .expect(cast(d(above), Float(Real)))
    .to_equal(@value.Value::from_float(one_up))
  })
}

///|
test "cast of a float to an integer uses its exact value" {
  // -2^63 is a double; its shortest text (-9223372036854776000) is not.
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_float(-9223372036854775808.0), int64))
    .to_equal(@value.Value::from_int(-9223372036854775808L))
    soft
    .expect(
      failure(() => cast(@value.Value::from_float(9223372036854775808.0), int64)),
    )
    .to_equal("data")
  })
}

///|
test "exponent text keeps its digits" {
  let digits = "1.2345678901234567890123456789012345678E47"
  @expect.expect_all(soft => {
    soft
    .expect(cast(@value.Value::from_string(digits), Decimal(Unconstrained)))
    .to_equal(d("1.2345678901234567890123456789012345678d47"))
    // Halfway in binary64 but above it in exact decimal: rounds up once.
    soft
    .expect(
      cast(
        @value.Value::from_string("1.00000005960464477539062500001e0"),
        Float(Real),
      ),
    )
    .to_equal(
      @value.Value::from_float(
        Float::from_double(1.0 + 1.0 / 8388608.0).to_double(),
      ),
    )
    soft
    .expect(
      failure(() => cast(@value.Value::from_string("1e400"), Float(Double))),
    )
    .to_equal("data")
    soft
    .expect(cast(@value.Value::from_string("1e400"), Decimal(Unconstrained)))
    .to_equal(d("1d400"))
    soft
    .expect(failure(() => cast(@value.Value::from_string("2e10"), int32)))
    .to_equal("data")
    soft
    .expect(cast(@value.Value::from_string("2.5e0"), int32))
    .to_equal(@value.Value::from_int(2))
  })
}
