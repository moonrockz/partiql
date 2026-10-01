///|
fn ion(text : String) -> @ion_core.IonValue raise {
  @text.read_ion(text)
}

///|
fn decode(text : String) -> @value.Value raise {
  @partiql_ion.from_ion(ion(text))
}

///|
fn i(n : Int) -> @value.Value {
  @value.Value::Int(n.to_int64())
}

///|
test "plain ion maps to core values" {
  @expect.expect_all(soft => {
    soft.expect(decode("null")).to_equal(@value.Value::Null)
    soft.expect(decode("null.int")).to_equal(@value.Value::Null)
    soft.expect(decode("abc")).to_equal(@value.Value::String("abc"))
    soft
    .expect(decode("[1, \"a\"]"))
    .to_equal(@value.Value::List([i(1), @value.Value::String("a")]))
    soft
    .expect(decode("{a: 1, b: $missing::null}"))
    .to_equal(@value.Value::Tuple(@value.Tuple::new([("a", i(1))])))
    soft
    .expect(decode("123456789012345678901234567890"))
    .to_equal(@value.Value::integer(123456789012345678901234567890N))
  })
}

///|
test "annotated forms" {
  @expect.expect_all(soft => {
    soft.expect(decode("$missing::null")).to_equal(@value.Value::Missing)
    soft
    .expect(decode("$bag::[1, 2]"))
    .to_equal(@value.Value::Bag(@value.Bag::new([i(1), i(2)])))
    soft
    .expect(decode("$date::{year: 2022, month: 2, day: 22}"))
    .to_equal(@value.Value::Date(@value.Date::new(year=2022, month=2, day=22)))
    soft
    .expect(decode("$time::{hour: 2, minute: 30, second: 59.25, offset: 0}"))
    .to_equal(
      @value.Value::Time(
        @value.Time::new(
          hour=2,
          minute=30,
          second=59,
          nanos=250000000,
          precision=2,
          offset=Some(0),
        ),
      ),
    )
    soft
    .expect(decode("$time::{hour: 2, minute: 30, second: 59., offset: null}"))
    .to_equal(
      @value.Value::Time(@value.Time::new(hour=2, minute=30, second=59)),
    )
    soft
    .expect(decode("$interval_ym::{sign: \"-\", years: 1, months: 6}"))
    .to_equal(@value.Value::IntervalYM(@value.IntervalYM::new(-18L)))
    soft
    .expect(decode("$interval_dt::{minutes: 90}"))
    .to_equal(@value.Value::IntervalDT(@value.IntervalDT::new(5400L, 0L)))
    match decode("$ion::a::(1 2)") {
      Ion(x) => soft.expect(x.equals(ion("a::(1 2)"))).to_be_true()
      other => fail("unexpected \{@debug.to_string(other)}")
    }
  })
}

///|
test "legacy forms decode like the new forms" {
  @expect.expect_all(soft => {
    soft
    .expect(decode("$date::2021-08-22"))
    .to_equal(decode("$date::{year: 2021, month: 8, day: 22}"))
    soft
    .expect(decode("$time::\"04:05:06\""))
    .to_equal(decode("$time::{hour: 4, minute: 5, second: 6., offset: null}"))
    soft
    .expect(
      decode(
        "$time::{hour: 4, minute: 5, second: 6., timezone_hour: null.int, timezone_minute: null.int}",
      ),
    )
    .to_equal(decode("$time::{hour: 4, minute: 5, second: 6., offset: null}"))
    soft
    .expect(
      decode(
        "$time::{hour: 4, minute: 5, second: 6., timezone_hour: 1, timezone_minute: 30}",
      ),
    )
    .to_equal(decode("$time::{hour: 4, minute: 5, second: 6., offset: 90}"))
  })
}

///|
test "unsupported and malformed inputs raise" {
  @expect.expect_all(soft => {
    for text in ["$graph::{nodes: [], edges: []}"] {
      soft
      .expect_call(() => decode(text), label=text)
      .to_raise_matching(
        e => e is @partiql_ion.CodecError::Unsupported(_),
        description="Unsupported",
      )
    }
    for
      text in [
        "(1 2)", "foo::1", "$date::{year: 2022, month: 13, day: 1}", "$time::{hour: 25, minute: 0, second: 0., offset: null}",
        "$time::{hour: 1, minute: 0, second: 0.1234567891, offset: null}", "$interval_ym::{sign: \"*\"}",
        "$date::{year: \"x\", month: 1, day: 1}", "$bag::1", "$missing::1",
      ] {
      soft
      .expect_call(() => decode(text), label=text)
      .to_raise_matching(malformed, description="Malformed")
    }
  })
}

///|
test "encode writes canonical forms" {
  let cases = [
    ("$missing::null", "$missing::null"),
    ("$bag::[1]", "$bag::[1]"),
    ("$date::2021-08-22", "$date::{year: 2021, month: 8, day: 22}"),
    (
      "$time::\"04:05:06\"", "$time::{hour: 4, minute: 5, second: 6., offset: null}",
    ),
    (
      "$interval_dt::{minutes: 90}", "$interval_dt::{sign: \"+\", days: 0, hours: 1, minutes: 30, seconds: 0, nanos: 0}",
    ),
    ("$ion::a::sym", "$ion::a::sym"),
    ("sym", "\"sym\""),
  ]
  @expect.expect_all(soft => {
    for case in cases {
      let encoded = @partiql_ion.to_ion(decode(case.0))
      soft.expect(encoded.equals(ion(case.1)), label=case.0).to_be_true()
    }
  })
}

///|
test "round trip" {
  @expect.expect_all(soft => {
    for
      text in [
        "{a: 1, b: [1.50, 2e0, $bag::[null]], c: $timestamp::{year: 2025, month: 1, day: 1, hour: 1, minute: 1, second: 1.111, offset: -2}}",
        "$interval_ym::{sign: \"-\", years: 2, months: 3}",
      ] {
      let v = decode(text)
      soft
      .expect(@partiql_ion.from_ion(@partiql_ion.to_ion(v)), label=text)
      .to_equal(v)
    }
  })
}

///|
fn malformed(e : Error) -> Bool {
  e is @partiql_ion.CodecError::Malformed(_)
}

///|
test "seconds with extreme exponents decode or fail fast" {
  @expect.expect_all(soft => {
    soft
    .expect(
      decode("$time::{hour: 1, minute: 0, second: 0d50000000, offset: null}"),
    )
    .to_equal(@value.Value::Time(@value.Time::new(hour=1, minute=0, second=0)))
    soft
    .expect_call(() => {
      decode("$time::{hour: 1, minute: 0, second: 1d2147483647, offset: null}")
    })
    .to_raise_matching(malformed, description="Malformed")
    let tiny = @ion_core.IonValue::from_fields([
      @ion_core.Field::new("hour", @ion_core.IonValue::int(1)),
      @ion_core.Field::new("minute", @ion_core.IonValue::int(0)),
      @ion_core.Field::new(
        "second",
        @ion_core.IonValue::decimal(@ion_core.Decimal::new(1N, -2147483648)),
      ),
      @ion_core.Field::new("offset", @ion_core.IonValue::untyped_null()),
    ]).with_annotation(@ion_core.SymbolToken::new("$time"))
    soft
    .expect_call(() => @partiql_ion.from_ion(tiny))
    .to_raise_matching(malformed, description="Malformed")
  })
}

///|
test "interval fields that overflow or are negative are malformed" {
  @expect.expect_all(soft => {
    for
      text in [
        "$interval_ym::{years: 9223372036854775807}", "$interval_dt::{days: 9223372036854775807}",
        "$interval_dt::{seconds: 9223372036854775807, nanos: 1000000000}", "$interval_dt::{sign: \"-\", nanos: -9223372036854775808}",
        "$interval_ym::{months: -1}",
      ] {
      soft
      .expect_call(() => decode(text), label=text)
      .to_raise_matching(malformed, description="Malformed")
    }
  })
}

///|
test "legacy zone fields out of range are malformed" {
  @expect.expect_all(soft => {
    for
      text in [
        "$time::{hour: 1, minute: 0, second: 0., timezone_hour: 71582788, timezone_minute: 0}",
        "$time::{hour: 1, minute: 0, second: 0., timezone_hour: 1, timezone_minute: 60}",
      ] {
      soft
      .expect_call(() => decode(text), label=text)
      .to_raise_matching(malformed, description="Malformed")
    }
  })
}

///|
fn map_value(
  key_type : @value.MapType,
  value_type : @value.MapType,
  pairs : Array[(@value.Value, @value.Value)],
) -> @value.Value raise {
  @value.Value::Map(@value.MapValue::new(key_type~, value_type~, pairs))
}

///|
test "$map values decode" {
  let s = (text : String) => @value.Value::String(text)
  @expect.expect_all(soft => {
    soft
    .expect(
      decode("$map::string::integer::[[\"math\", 90], [\"science\", 85]]"),
    )
    .to_equal(
      map_value(String, Integer, [(s("math"), i(90)), (s("science"), i(85))]),
    )
    soft
    .expect(decode("$map::string::dynamic::[]"))
    .to_equal(map_value(String, Dynamic, []))
    soft
    .expect(decode("$map::string::integer::[[\"a\", 1], [\"b\", null]]"))
    .to_equal(
      map_value(String, Integer, [(s("a"), i(1)), (s("b"), @value.Value::Null)]),
    )
    soft
    .expect(decode("$map::bool::string::[[true, \"yes\"], [false, \"no\"]]"))
    .to_equal(
      map_value(Bool, String, [
        (@value.Value::Bool(true), s("yes")),
        (@value.Value::Bool(false), s("no")),
      ]),
    )
    soft
    .expect(decode("$map::string::integer::null"))
    .to_equal(@value.Value::Null)
  })
}

///|
test "$map date keys written as Ion timestamps decode to dates" {
  let date = @value.Value::Date(@value.Date::new(year=2024, month=1, day=1))
  @expect.expect(decode("$map::date::string::[[2024-01-01, \"new year\"]]")).to_equal(
    map_value(Date, String, [(date, @value.Value::String("new year"))]),
  )
}

///|
test "$map round trip" {
  @expect.expect_all(soft => {
    for
      text in [
        "$map::decimal::string::[[2., \"two\"], [1.0, \"yes\"]]", "$map::date::string::[[2024-01-01, \"x\"]]",
        "$map::string::bigint::[[\"a\", 1]]", "{m: $map::integer::string::[[1, \"one\"]]}",
      ] {
      let v = decode(text)
      soft
      .expect(@partiql_ion.from_ion(@partiql_ion.to_ion(v)), label=text)
      .to_equal(v)
    }
  })
}

///|
test "malformed $map values raise" {
  @expect.expect_all(soft => {
    for
      text in [
        "$map::string::[]", "$map::string::integer::extra::[]", "$map::foo::integer::[]",
        "$map::string::integer::[[\"a\"]]", "$map::string::integer::[1]", "$map::string::integer::[[null, 1]]",
        "$map::string::integer::[[\"a\", 1], [\"a\", 2]]", "$map::dynamic::integer::[]",
        "$map::string::integer::{}",
      ] {
      soft
      .expect_call(() => decode(text), label=text)
      .to_raise_matching(malformed, description="Malformed")
    }
  })
}

///|
test "$map date coercion applies only to day-precision timestamps" {
  match decode("$map::string::date::[[\"a\", 2024-01-01T10:30Z]]") {
    Map(m) => @expect.expect(m.entries()[0].1 is Timestamp(_)).to_be_true()
    other => fail("unexpected \{@debug.to_string(other)}")
  }
}

///|
test "map timestamps in date positions round trip without coercion" {
  let ts = @value.Value::Timestamp(
    @value.Timestamp::new(
      @value.Date::new(year=2024, month=1, day=1),
      @value.Time::new(hour=0, minute=0, second=0, offset=Some(0)),
    ),
  )
  let date = @value.Value::Date(@value.Date::new(year=2024, month=1, day=1))
  let m = map_value(Date, Date, [(ts, @value.Value::String("x")), (date, ts)])
  @expect.expect_all(soft => {
    soft.expect(@partiql_ion.from_ion(@partiql_ion.to_ion(m))).to_equal(m)
    // Only a plain day-precision Ion timestamp is a date.
    match decode("$map::string::date::[[\"a\", 2024-01-01T00:00:00.000Z]]") {
      Map(decoded) =>
        soft.expect(decoded.entries()[0].1 is Timestamp(_)).to_be_true()
      other => fail("unexpected \{@debug.to_string(other)}")
    }
  })
}

///|
test "map keys are checked even when the value is MISSING" {
  @expect.expect_all(soft => {
    for
      text in [
        "$map::string::integer::[[null, $missing::null]]", "$map::string::integer::[[[\"x\"], $missing::null]]",
        "$map::string::integer::[[\"a\", 1], [\"a\", $missing::null]]", "$map::string::integer::[foo::[\"a\", 1]]",
      ] {
      soft
      .expect_call(() => decode(text), label=text)
      .to_raise_matching(malformed, description="Malformed")
    }
  })
}
