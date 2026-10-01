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
  for text in ["$map::string::integer::[]", "$graph::{nodes: [], edges: []}"] {
    try decode(text) catch {
      @partiql_ion.CodecError::Unsupported(_) => ()
      other => fail("\{text}: \{@debug.to_string(other)}")
    } noraise {
      v => fail("\{text} decoded to \{@debug.to_string(v)}")
    }
  }
  for
    text in [
      "(1 2)", "foo::1", "$date::{year: 2022, month: 13, day: 1}", "$time::{hour: 25, minute: 0, second: 0., offset: null}",
      "$time::{hour: 1, minute: 0, second: 0.1234567891, offset: null}", "$interval_ym::{sign: \"*\"}",
      "$date::{year: \"x\", month: 1, day: 1}", "$bag::1", "$missing::1",
    ] {
    try decode(text) catch {
      @partiql_ion.CodecError::Malformed(_) => ()
      other => fail("\{text}: \{@debug.to_string(other)}")
    } noraise {
      v => fail("\{text} decoded to \{@debug.to_string(v)}")
    }
  }
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
  for case in cases {
    let encoded = @partiql_ion.to_ion(decode(case.0))
    @expect.expect(encoded.equals(ion(case.1)), label=case.0).to_be_true()
  }
}

///|
test "round trip" {
  for
    text in [
      "{a: 1, b: [1.50, 2e0, $bag::[null]], c: $timestamp::{year: 2025, month: 1, day: 1, hour: 1, minute: 1, second: 1.111, offset: -2}}",
      "$interval_ym::{sign: \"-\", years: 2, months: 3}",
    ] {
    let v = decode(text)
    @expect.expect(@partiql_ion.from_ion(@partiql_ion.to_ion(v)), label=text).to_equal(
      v,
    )
  }
}
