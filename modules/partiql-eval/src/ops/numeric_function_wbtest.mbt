///|
fn d(text : String) -> @value.Value raise {
  @value.Value::from_decimal(@ion_core.Decimal::parse(text))
}

///|
test "ABS keeps the type and the scale" {
  @expect.expect_all(soft => {
    soft
    .expect(abs([@value.Value::from_int(-5)]))
    .to_equal(@value.Value::from_int(5))
    soft
    .expect(abs([@value.Value::from_int(5)]))
    .to_equal(@value.Value::from_int(5))
    soft
    .expect(failure(() => abs([@value.Value::from_int(-9223372036854775808L)])))
    .to_equal("data")
    soft.expect(abs([d("-1.0")])).to_equal(d("1.0"))
    soft
    .expect(abs([d("-1.9999999999999999999900")]))
    .to_equal(d("1.9999999999999999999900"))
    soft.expect(abs([d("-0.0000")])).to_equal(d("0.0000"))
    soft
    .expect(abs([@value.Value::from_float(-1.0)]))
    .to_equal(@value.Value::from_float(1.0))
    soft
    .expect(abs([@value.Value::from_float(-1.0 / 0.0)]))
    .to_equal(@value.Value::from_float(1.0 / 0.0))
    soft.expect(abs([Null])).to_equal(Null)
    soft.expect(abs([Missing])).to_equal(Missing)
    soft
    .expect(failure(() => abs([@value.Value::from_string("foo")])))
    .to_equal("type")
  })
}

///|
test "ABS of an interval has sign +" {
  let negative_ym = @value.Value::from_interval_ym(@value.IntervalYM(-18L))
  let negative_dt = @value.Value::from_interval_dt(
    @value.IntervalDT(-123L, -456789000L),
  )
  @expect.expect_all(soft => {
    soft
    .expect(abs([negative_ym]))
    .to_equal(@value.Value::from_interval_ym(@value.IntervalYM(18L)))
    soft
    .expect(abs([negative_dt]))
    .to_equal(
      @value.Value::from_interval_dt(@value.IntervalDT(123L, 456789000L)),
    )
  })
}

///|
test "MOD has the sign of the dividend" {
  let fraction = d("1.5")
  @expect.expect_all(soft => {
    soft
    .expect(modulo([@value.Value::from_int(-17), @value.Value::from_int(4)]))
    .to_equal(@value.Value::from_int(-1))
    soft
    .expect(modulo([@value.Value::from_int(17), @value.Value::from_int(-4)]))
    .to_equal(@value.Value::from_int(1))
    soft
    .expect(
      modulo([
        @value.Value::from_int(-9223372036854775808L),
        @value.Value::from_int(-1),
      ]),
    )
    .to_equal(@value.Value::from_int(0))
    soft.expect(modulo([d("7."), @value.Value::from_int(4)])).to_equal(d("3."))
    soft
    .expect(
      failure(() => {
        modulo([@value.Value::from_int(1), @value.Value::from_int(0)])
      }),
    )
    .to_equal("data")
    soft
    .expect(failure(() => modulo([fraction, @value.Value::from_int(1)])))
    .to_equal("type")
    soft
    .expect(
      failure(() => {
        modulo([@value.Value::from_float(1.0), @value.Value::from_int(1)])
      }),
    )
    .to_equal("type")
    soft
    .expect(failure(() => modulo([Missing, @value.Value::from_string("a")])))
    .to_equal("type")
    soft
    .expect(failure(() => modulo([Null, @value.Value::from_string("a")])))
    .to_equal("type")
    soft.expect(modulo([Missing, Null])).to_equal(Missing)
    soft.expect(modulo([@value.Value::from_int(1), Null])).to_equal(Null)
  })
}
