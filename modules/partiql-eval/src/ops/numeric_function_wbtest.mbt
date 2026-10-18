///|
fn d(text : String) -> @value.Value raise {
  Decimal(@ion_core.Decimal::parse(text))
}

///|
test "ABS keeps the type and the scale" {
  @expect.expect_all(soft => {
    soft.expect(abs([Int(-5)])).to_equal(Int(5))
    soft.expect(abs([Int(5)])).to_equal(Int(5))
    soft
    .expect(failure(() => abs([Int(-9223372036854775808L)])))
    .to_equal("data")
    soft.expect(abs([d("-1.0")])).to_equal(d("1.0"))
    soft
    .expect(abs([d("-1.9999999999999999999900")]))
    .to_equal(d("1.9999999999999999999900"))
    soft.expect(abs([d("-0.0000")])).to_equal(d("0.0000"))
    soft.expect(abs([Float(-1.0)])).to_equal(Float(1.0))
    soft.expect(abs([Float(-1.0 / 0.0)])).to_equal(Float(1.0 / 0.0))
    soft.expect(abs([Null])).to_equal(Null)
    soft.expect(abs([Missing])).to_equal(Missing)
    soft.expect(failure(() => abs([String("foo")]))).to_equal("type")
  })
}

///|
test "ABS of an interval has sign +" {
  let negative_ym = @value.Value::IntervalYM(
    @value.IntervalYM::IntervalYM(-18L),
  )
  let negative_dt = @value.Value::IntervalDT(
    @value.IntervalDT::IntervalDT(-123L, -456789000L),
  )
  @expect.expect_all(soft => {
    soft
    .expect(abs([negative_ym]))
    .to_equal(IntervalYM(@value.IntervalYM::IntervalYM(18L)))
    soft
    .expect(abs([negative_dt]))
    .to_equal(IntervalDT(@value.IntervalDT::IntervalDT(123L, 456789000L)))
  })
}

///|
test "MOD has the sign of the dividend" {
  let fraction = d("1.5")
  @expect.expect_all(soft => {
    soft.expect(modulo([Int(-17), Int(4)])).to_equal(Int(-1))
    soft.expect(modulo([Int(17), Int(-4)])).to_equal(Int(1))
    soft.expect(modulo([Int(-9223372036854775808L), Int(-1)])).to_equal(Int(0))
    soft.expect(modulo([d("7."), Int(4)])).to_equal(d("3."))
    soft.expect(failure(() => modulo([Int(1), Int(0)]))).to_equal("data")
    soft.expect(failure(() => modulo([fraction, Int(1)]))).to_equal("type")
    soft.expect(failure(() => modulo([Float(1.0), Int(1)]))).to_equal("type")
    soft.expect(failure(() => modulo([Missing, String("a")]))).to_equal("type")
    soft.expect(failure(() => modulo([Null, String("a")]))).to_equal("type")
    soft.expect(modulo([Missing, Null])).to_equal(Missing)
    soft.expect(modulo([Int(1), Null])).to_equal(Null)
  })
}
