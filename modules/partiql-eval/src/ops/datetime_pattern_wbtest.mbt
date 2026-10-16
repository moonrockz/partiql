///|
fn fmt(x : @value.Value, pattern : String) -> @value.Value raise OpFailure {
  datetime_to_string([x, String(pattern)])
}

///|
fn moment(
  year : Int32,
  month : Int32,
  day : Int32,
  hour : Int32,
  minute : Int32,
  second : Int32,
  nanos : Int32,
  offset : Int32?,
) -> @value.Value {
  try
    @value.Value::Timestamp(
      @value.Timestamp::new(
        @value.Date::new(year~, month~, day~),
        @value.Time::new(hour~, minute~, second~, nanos~, precision=9, offset~),
      ),
    )
  catch {
    _ => Missing
  } noraise {
    v => v
  }
}

///|
test "tokenize: symbols, quotes and literals" {
  @expect.expect_all(soft => {
    soft.expect(tokenize("y-MM-dd").length()).to_equal(5)
    // Inside quotes `''` is a quote: `'T'''` is the text "T'".
    soft.expect(tokenize("'T'''").length()).to_equal(1)
    for
      bad in [
        "G", "u", "yyy", "yyyyy", "MMMMMM", "ddd", "SSSSSSSSSS", "aa", "nn", "XXXXXX",
        "'open", "not_a_pattern", "k", "z",
      ] {
      soft
      .expect(
        (bad, failure(() => fmt(moment(2020, 1, 1, 0, 0, 0, 0, Some(0)), bad))),
      )
      .to_equal((bad, "data"))
    }
  })
}

///|
test "TO_STRING formats every symbol" {
  let t = moment(986, 1, 2, 3, 4, 5, 4000000, Some(-330))
  let utc = moment(2017, 11, 21, 0, 0, 0, 0, Some(0))
  let pm = moment(2017, 11, 21, 15, 7, 9, 123456789, Some(90))
  @expect.expect_all(soft => {
    soft.expect(fmt(t, "y")).to_equal(String("986"))
    soft.expect(fmt(t, "yy")).to_equal(String("86"))
    soft.expect(fmt(t, "yyyy")).to_equal(String("0986"))
    soft
    .expect(fmt(t, "M MM MMM MMMM MMMMM"))
    .to_equal(String("1 01 Jan January J"))
    soft.expect(fmt(t, "d dd")).to_equal(String("2 02"))
    soft.expect(fmt(t, "H HH h hh a")).to_equal(String("3 03 3 03 AM"))
    soft.expect(fmt(utc, "h a")).to_equal(String("12 AM"))
    soft.expect(fmt(pm, "h a")).to_equal(String("3 PM"))
    soft.expect(fmt(t, "m mm s ss")).to_equal(String("4 04 5 05"))
    soft.expect(fmt(t, "SS SSS n")).to_equal(String("00 004 4000000"))
    soft.expect(fmt(pm, "SSSSSSSSS")).to_equal(String("123456789"))
    soft.expect(fmt(t, "X XX XXX")).to_equal(String("-0530 -0530 -05:30"))
    soft.expect(fmt(pm, "X")).to_equal(String("+0130"))
    soft
    .expect(fmt(utc, "X XXX x xx xxx"))
    .to_equal(String("Z Z +00 +0000 +00:00"))
    soft
    .expect(fmt(utc, "yyyy-MM-dd'T'HH:mm:ss''X"))
    .to_equal(String("2017-11-21T00:00:00'Z"))
    soft.expect(fmt(utc, "y😀M")).to_equal(String("2017😀11"))
  })
}

///|
test "TO_STRING: types and fields the value lacks" {
  let date = try
    @value.Value::Date(@value.Date::new(year=2020, month=3, day=4))
  catch {
    _ => @value.Value::Missing
  } noraise {
    v => v
  }
  let no_zone = moment(2020, 3, 4, 5, 6, 7, 0, None)
  @expect.expect_all(soft => {
    soft.expect(fmt(date, "yyyy-MM-dd")).to_equal(String("2020-03-04"))
    soft.expect(failure(() => fmt(date, "HH"))).to_equal("data")
    soft.expect(failure(() => fmt(no_zone, "X"))).to_equal("data")
    soft.expect(failure(() => fmt(Int(1), "y"))).to_equal("type")
    soft
    .expect(failure(() => datetime_to_string([date, Int(1)])))
    .to_equal("type")
    soft.expect(datetime_to_string([Null, String("G")])).to_equal(Null)
    soft.expect(datetime_to_string([Null, Missing])).to_equal(Missing)
  })
}
