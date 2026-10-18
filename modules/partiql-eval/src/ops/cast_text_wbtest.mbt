///|
fn text_cast(x : @value.Value, kind : TextKind) -> @value.Value raise OpFailure {
  cast(x, Text(kind))
}

///|
test "decimal text" {
  @expect.expect_all(soft => {
    soft.expect(decimal_text(dec("1.50"))).to_equal("1.50")
    soft.expect(decimal_text(dec("-0.5"))).to_equal("-0.5")
    soft.expect(decimal_text(dec("0.001"))).to_equal("0.001")
    soft.expect(decimal_text(dec("123.456"))).to_equal("123.456")
    soft.expect(decimal_text(dec("1d3"))).to_equal("1000")
    soft.expect(decimal_text(dec("-0.0"))).to_equal("0.0")
    soft.expect(decimal_text(dec("0d5"))).to_equal("0")
    soft.expect(decimal_text(dec("1.5d50"))).to_equal("1.5E50")
    soft.expect(decimal_text(dec("1d-60"))).to_equal("1E-60")
    soft.expect(decimal_text(dec("1d1000000000"))).to_equal("1E1000000000")
    soft.expect(decimal_text(dec("0d-2000000000"))).to_equal("0E-2000000000")
    soft
    .expect(decimal_text(dec("99999999999999999999999999999999999999")))
    .to_equal("99999999999999999999999999999999999999")
  })
}

///|
test "float text" {
  @expect.expect_all(soft => {
    soft.expect(float_text(1.5)).to_equal("1.5E0")
    soft.expect(float_text(-0.0025)).to_equal("-2.5E-3")
    soft.expect(float_text(100.0)).to_equal("1E2")
    soft.expect(float_text(0.1)).to_equal("1E-1")
    soft.expect(float_text(0.0)).to_equal("0E0")
    soft.expect(float_text(-0.0)).to_equal("-0E0")
    soft.expect(float_text(1.0e300)).to_equal("1E300")
    soft.expect(float_text(0.0 / 0.0)).to_equal("nan")
    soft.expect(float_text(1.0 / 0.0)).to_equal("+inf")
    soft.expect(float_text(-1.0 / 0.0)).to_equal("-inf")
  })
}

///|
test "datetime and interval text" {
  let time = @value.Time::Time(
    hour=1,
    minute=2,
    second=3,
    nanos=450000000,
    precision=2,
    offset=Some(-330),
  )
  let whole = @value.Time::Time(hour=23, minute=0, second=0, precision=0)
  let utc = @value.Time::Time(
    hour=0,
    minute=0,
    second=0,
    precision=0,
    offset=Some(0),
  )
  let day = @value.Date::Date(year=2026, month=3, day=7)
  @expect.expect_all(soft => {
    soft.expect(date_text(day)).to_equal("2026-03-07")
    soft
    .expect(date_text(@value.Date::Date(year=10000, month=1, day=1)))
    .to_equal("10000-01-01")
    soft.expect(time_text(time)).to_equal("01:02:03.45-05:30")
    soft.expect(time_text(whole)).to_equal("23:00:00")
    soft.expect(time_text(utc)).to_equal("00:00:00+00:00")
    soft
    .expect(display_text(Timestamp(@value.Timestamp::Timestamp(day, time))))
    .to_equal(Some("TIMESTAMP '2026-03-07 01:02:03.45-05:30'"))
    soft
    .expect(display_text(IntervalYM(@value.IntervalYM::IntervalYM(-14L))))
    .to_equal(Some("INTERVAL '-1-2' YEAR TO MONTH"))
    soft
    .expect(
      display_text(
        IntervalDT(@value.IntervalDT::IntervalDT(273906L, 500000000L)),
      ),
    )
    .to_equal(Some("INTERVAL '3 04:05:06.5' DAY TO SECOND"))
    soft
    .expect(display_text(IntervalDT(@value.IntervalDT::IntervalDT(-1L, 0L))))
    .to_equal(Some("INTERVAL '-0 00:00:01' DAY TO SECOND"))
    // SQL 6.13: the text of a datetime or interval is an SQL <literal>.
    soft.expect(display_text(Date(day))).to_equal(Some("DATE '2026-03-07'"))
    soft
    .expect(display_text(Time(time)))
    .to_equal(Some("TIME '01:02:03.45-05:30'"))
    // Precisions beyond the defaults (leading 2, fraction 6) are written out,
    // so that the literal reads back.
    soft
    .expect(
      display_text(IntervalDT(@value.IntervalDT::IntervalDT(123L * 86400L, 0L))),
    )
    .to_equal(Some("INTERVAL '123 00:00:00' DAY(3) TO SECOND"))
    soft
    .expect(
      display_text(IntervalDT(@value.IntervalDT::IntervalDT(0L, 123456789L))),
    )
    .to_equal(Some("INTERVAL '0 00:00:00.123456789' DAY TO SECOND(9)"))
    soft
    .expect(display_text(IntervalYM(@value.IntervalYM::IntervalYM(1800L))))
    .to_equal(Some("INTERVAL '150-0' YEAR(3) TO MONTH"))
    soft.expect(display_text(Bool(true))).to_equal(Some("TRUE"))
    soft.expect(display_text(List([]))).to_equal(None)
  })
}

///|
test "cast to character strings" {
  @expect.expect_all(soft => {
    soft.expect(text_cast(String("abc"), String)).to_equal(String("abc"))
    soft.expect(text_cast(String("abcdef"), Varchar(3))).to_equal(String("abc"))
    soft.expect(text_cast(String("ab"), Varchar(3))).to_equal(String("ab"))
    soft.expect(text_cast(String("ab"), Char(4))).to_equal(String("ab  "))
    soft.expect(text_cast(String("abcdef"), Char(2))).to_equal(String("ab"))
    soft
    .expect(text_cast(String("a😀b"), Varchar(2)))
    .to_equal(String("a😀"))
    soft.expect(text_cast(String("😀"), Char(3))).to_equal(String("😀  "))
    soft.expect(text_cast(Int(12345), String)).to_equal(String("12345"))
    soft.expect(text_cast(Int(123), Char(3))).to_equal(String("123"))
    soft.expect(text_cast(Int(12), Char(3))).to_equal(String("12 "))
    soft.expect(failure(() => text_cast(Int(12345), Char(3)))).to_equal("data")
    soft
    .expect(failure(() => text_cast(Bool(false), Varchar(4))))
    .to_equal("data")
    soft.expect(text_cast(Bool(false), String)).to_equal(String("FALSE"))
    soft.expect(text_cast(Float(1.5), String)).to_equal(String("1.5E0"))
    soft.expect(text_cast(dn("1.50"), String)).to_equal(String("1.50"))
    soft.expect(text_cast(Clob(b"abc"), String)).to_equal(String("abc"))
    soft
    .expect(failure(() => text_cast(Clob(b"\xff"), String)))
    .to_equal("type")
    soft.expect(failure(() => text_cast(Blob(b"abc"), String))).to_equal("type")
    soft.expect(failure(() => text_cast(List([]), String))).to_equal("type")
    let symbol = @value.Value::Ion(@ion_core.IonValue::symbol("abc"))
    soft.expect(text_cast(symbol, String)).to_equal(String("abc"))
  })
}

///|
test "cast to CLOB and BLOB" {
  @expect.expect_all(soft => {
    soft.expect(cast(String("é"), Clob)).to_equal(Clob(b"\xc3\xa9"))
    soft.expect(cast(Blob(b"ab"), Clob)).to_equal(Clob(b"ab"))
    soft.expect(cast(Clob(b"ab"), Blob)).to_equal(Blob(b"ab"))
    soft.expect(failure(() => cast(String("ab"), Blob))).to_equal("type")
    soft.expect(failure(() => cast(Int(1), Clob))).to_equal("type")
  })
}
