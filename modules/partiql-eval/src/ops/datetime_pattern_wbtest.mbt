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

///|
fn parse_ts(text : String, pattern : String) -> @value.Value raise OpFailure {
  text_to_timestamp([String(text), String(pattern)])
}

///|
fn stamp_of(
  year : Int32,
  month : Int32,
  day : Int32,
  hour : Int32,
  minute : Int32,
  second : Int32,
  nanos : Int32,
  precision : Int32,
  offset : Int32,
) -> @value.Value {
  try
    @value.Value::Timestamp(
      @value.Timestamp::new(
        @value.Date::new(year~, month~, day~),
        @value.Time::new(
          hour~,
          minute~,
          second~,
          nanos~,
          precision~,
          offset=Some(offset),
        ),
      ),
    )
  catch {
    _ => @value.Value::Missing
  } noraise {
    v => v
  }
}

///|
test "TO_TIMESTAMP parses with a pattern" {
  @expect.expect_all(soft => {
    soft
    .expect(parse_ts("2007", "y"))
    .to_equal(stamp_of(2007, 1, 1, 0, 0, 0, 0, 0, 0))
    soft
    .expect(parse_ts("1 1 1 0 0 0 10", "y M d H m s SS"))
    .to_equal(stamp_of(1, 1, 1, 0, 0, 0, 100000000, 1, 0))
    soft
    .expect(parse_ts("2007-06-05T04:03:02+01:30", "yyyy-MM-dd'T'HH:mm:ssXXX"))
    .to_equal(stamp_of(2007, 6, 5, 4, 3, 2, 0, 0, 90))
    soft
    .expect(parse_ts("69", "yy"))
    .to_equal(stamp_of(2069, 1, 1, 0, 0, 0, 0, 0, 0))
    soft
    .expect(parse_ts("70", "yy"))
    .to_equal(stamp_of(1970, 1, 1, 0, 0, 0, 0, 0, 0))
    soft
    .expect(parse_ts("2020 jAn 1 12 am", "y MMM d h a"))
    .to_equal(stamp_of(2020, 1, 1, 0, 0, 0, 0, 0, 0))
    soft
    .expect(parse_ts("2020 DECEMBER 31 11 PM", "y MMMM d h a"))
    .to_equal(stamp_of(2020, 12, 31, 23, 0, 0, 0, 0, 0))
    soft
    .expect(parse_ts("2020-01-01 00:00:00 Z", "y-M-d H:m:s X"))
    .to_equal(stamp_of(2020, 1, 1, 0, 0, 0, 0, 0, 0))
    soft
    .expect(parse_ts("2020年", "y'年'"))
    .to_equal(stamp_of(2020, 1, 1, 0, 0, 0, 0, 0, 0))
    soft
    .expect(parse_ts("2020 1 1 1 1 1 5", "y M d H m s n"))
    .to_equal(stamp_of(2020, 1, 1, 1, 1, 1, 5, 9, 0))
  })
}

///|
test "TO_TIMESTAMP: pattern checks" {
  @expect.expect_all(soft => {
    for
      pattern in [
        "y MMMMM", "y y", "M d", "y d", "y M X", "y M d h", "y M d H a", "yMd", "y M d m",
      ] {
      soft
      .expect((pattern, failure(() => parse_ts("2020 1 1 1", pattern))))
      .to_equal((pattern, "data"))
    }
  })
}

///|
test "TO_TIMESTAMP: text that does not match or is out of range" {
  @expect.expect_all(soft => {
    for
      case in [
        ("10000", "y"),
        ("0", "y"),
        ("-5", "y"),
        ("99999999999999999999", "y"),
        ("010", "yy"),
        ("010", "yyyy"),
        ("00010", "yyyy"),
        ("1", "MM"),
        ("2020 13", "y M"),
        ("2021 2 29", "y M d"),
        ("2020 1 1 24", "y M d H"),
        ("2020 1 1 13 AM", "y M d h a"),
        ("2020 1 1 0 +1", "y M d H X"),
        ("2020 1 1 0 05", "y M d H X"),
        ("2020 1 1 0 +24", "y M d H X"),
        ("2020 1 1 0 Z", "y M d H x"),
        ("2020 x", "y"),
        ("2020", "y M"),
      ] {
      let (text, pattern) = case
      soft
      .expect((text, pattern, failure(() => parse_ts(text, pattern))))
      .to_equal((text, pattern, "data"))
    }
  })
}

///|
test "TO_TIMESTAMP with one argument reads Ion timestamp text" {
  @expect.expect_all(soft => {
    soft
    .expect(text_to_timestamp([String("2007-02-23T12:14:33.079-08:00")]))
    .to_equal(stamp_of(2007, 2, 23, 12, 14, 33, 79000000, 3, -480))
    soft
    .expect(failure(() => text_to_timestamp([String("2007-02-23 12:14")])))
    .to_equal("data")
    soft.expect(text_to_timestamp([Null])).to_equal(Null)
    soft.expect(text_to_timestamp([Missing])).to_equal(Missing)
    soft.expect(failure(() => text_to_timestamp([Int(1)]))).to_equal("type")
  })
}

///|
test "TO_TIMESTAMP: S x n reads exactly n digits" {
  @expect.expect_all(soft => {
    soft
    .expect(parse_ts("2020-01-01 00:00:00.5", "yyyy-MM-dd HH:mm:ss.S"))
    .to_equal(stamp_of(2020, 1, 1, 0, 0, 0, 500000000, 1, 0))
    soft
    .expect(
      failure(() => parse_ts("2020-01-01 00:00:00.05", "yyyy-MM-dd HH:mm:ss.S")),
    )
    .to_equal("data")
    soft
    .expect(
      failure(() => {
        parse_ts(
          "2020-01-01 00:00:00.28999941890838049", "yyyy-MM-dd HH:mm:ss.S",
        )
      }),
    )
    .to_equal("data")
  })
}

///|
test "TO_TIMESTAMP: only month names and AM/PM ignore case" {
  // KDOC: "Month names and AM/PM specifiers are case-insensitive."
  @expect.expect_all(soft => {
    soft
    .expect(failure(() => parse_ts("2020-01-01t00", "yyyy-MM-dd'T'HH")))
    .to_equal("data")
    soft
    .expect(parse_ts("2020-01-01T00", "yyyy-MM-dd'T'HH"))
    .to_equal(stamp_of(2020, 1, 1, 0, 0, 0, 0, 0, 0))
    soft
    .expect(failure(() => parse_ts("2020 1 1 0 z", "y M d H X")))
    .to_equal("data")
  })
}

///|
test "TO_TIMESTAMP: XXXX and XXXXX accept zero offset seconds" {
  // KDOC: '+08:00:00' parses; '+08:00:01' is not on a minute boundary.
  @expect.expect_all(soft => {
    soft
    .expect(parse_ts("2020 1 1 0 +08:00:00", "y M d H XXXXX"))
    .to_equal(stamp_of(2020, 1, 1, 0, 0, 0, 0, 0, 480))
    soft
    .expect(parse_ts("2020 1 1 0 +080000", "y M d H XXXX"))
    .to_equal(stamp_of(2020, 1, 1, 0, 0, 0, 0, 0, 480))
    soft
    .expect(parse_ts("2020 1 1 0 -05:30:00", "y M d H xxxxx"))
    .to_equal(stamp_of(2020, 1, 1, 0, 0, 0, 0, 0, -330))
    soft
    .expect(failure(() => parse_ts("2020 1 1 0 +08:00:01", "y M d H XXXXX")))
    .to_equal("data")
    soft
    .expect(failure(() => parse_ts("2020 1 1 0 +08:00:00", "y M d H XXX")))
    .to_equal("data")
  })
}
