///|
fn v(a : @arbitrary.ArbValue) -> @value.Value {
  a.value
}

///|
test "Eq is reflexive and symmetric" {
  @quickcheck.check(
    (p : (@arbitrary.ArbValue, @arbitrary.ArbValue)) => {
      let (a, b) = (v(p.0), v(p.1))
      a == a && (a == b) == (b == a)
    },
    count=200,
  )
}

///|
test "bags and tuples ignore order" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      match v(a) {
        Bag(bag) =>
          @value.Value::Bag(@value.Bag::new(bag.items().to_owned().rev())) ==
          v(a)
        Tuple(t) =>
          @value.Value::Tuple(@value.Tuple::new(t.fields().to_owned().rev())) ==
          v(a)
        _ => true
      }
    },
    count=200,
  )
}

///|
test "tuples never hold MISSING" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      match v(a) {
        Tuple(t) => t.fields().iter().all(pair => !(pair.1 is Missing))
        _ => true
      }
    },
    count=200,
  )
}

///|
test "lower_deep is idempotent and removes boxed Ion" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      let once = v(a).lower_deep()
      let twice = once.lower_deep()
      once == twice && !contains_ion(once)
    },
    count=200,
  )
}

///|
fn contains_ion(x : @value.Value) -> Bool {
  match x {
    Ion(_) => true
    List(items) => items.iter().any(contains_ion)
    Bag(b) => b.items().iter().any(contains_ion)
    Tuple(t) => t.fields().iter().any(pair => contains_ion(pair.1))
    _ => false
  }
}

///|
test "sql_equals is symmetric and returns only Bool, Null or Missing" {
  @quickcheck.check(
    (p : (@arbitrary.ArbValue, @arbitrary.ArbValue)) => {
      let (a, b) = (v(p.0), v(p.1))
      let r = @value.sql_equals(a, b)
      r == @value.sql_equals(b, a) && r is (Bool(_) | Null | Missing)
    },
    count=200,
  )
}

///|
test "MISSING beats NULL" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      @value.sql_equals(@value.Value::Missing, v(a)) == @value.Value::Missing &&
      (
        v(a) is Missing ||
        @value.sql_equals(@value.Value::Null, v(a)) == @value.Value::Null
      )
    },
    count=200,
  )
}

///|
test "eqg is reflexive and symmetric" {
  @quickcheck.check(
    (p : (@arbitrary.ArbValue, @arbitrary.ArbValue)) => {
      let (a, b) = (v(p.0), v(p.1))
      @value.eqg(a, a) && @value.eqg(a, b) == @value.eqg(b, a)
    },
    count=200,
  )
}

///|
test "eqg is transitive" {
  @quickcheck.check(
    (t : (@arbitrary.ArbValue, @arbitrary.ArbValue, @arbitrary.ArbValue)) => {
      let (a, b, c) = (v(t.0), v(t.1), v(t.2))
      !(@value.eqg(a, b) && @value.eqg(b, c)) || @value.eqg(a, c)
    },
    count=200,
  )
}

///|
test "numbers of different kinds are eqg-equal when equal in value" {
  @quickcheck.check(
    (n : Int) => {
      let big = @bigint.BigInt::from_int(n)
      let values : Array[@value.Value] = [
        @value.Value::Int(n.to_int64()),
        @value.Value::Decimal(@ion_core.Decimal::new(big * 100N, -2)),
        @value.Value::Float(n.to_double()),
      ]
      values.iter().all(x => values.iter().all(y => @value.eqg(x, y)))
    },
    count=200,
  )
}

///|
test "compare is a total order consistent with eqg" {
  @quickcheck.check(
    (t : (@arbitrary.ArbValue, @arbitrary.ArbValue, @arbitrary.ArbValue)) => {
      let (a, b, c) = (v(t.0), v(t.1), v(t.2))
      let cmp = (x, y) => @value.compare(x, y, nulls=NullsFirst)
      let reflexive = cmp(a, a) == 0
      let antisymmetric = cmp(a, b) == -cmp(b, a)
      let transitive = !(cmp(a, b) <= 0 && cmp(b, c) <= 0) || cmp(a, c) <= 0
      let agrees = a is (Null | Missing) ||
        b is (Null | Missing) ||
        @arbitrary.has_nested_absent(a) ||
        @arbitrary.has_nested_absent(b) ||
        (cmp(a, b) == 0) == @value.eqg(a, b)
      reflexive && antisymmetric && transitive && agrees
    },
    count=200,
  )
}

///|
test "moving clock and offset together keeps a timestamp equal" {
  @quickcheck.check(
    (a : @arbitrary.ArbTimestamp) => {
      let ts = a.value
      guard ts.time.offset is Some(offset) else { return true }
      // Shift by one hour within the same day when possible.
      guard ts.time.hour < 23 && offset + 60 <= 1439 else { return true }
      let shifted = @value.Timestamp::new(
        ts.date,
        @value.Time::new(
          hour=ts.time.hour + 1,
          minute=ts.time.minute,
          second=ts.time.second,
          nanos=ts.time.nanos,
          precision=ts.time.precision,
          offset=Some(offset + 60),
        ),
      )
      @value.sql_equals(
        @value.Value::Timestamp(ts),
        @value.Value::Timestamp(shifted),
      ) ==
      @value.Value::Bool(true)
    },
    count=200,
  )
}

///|
test "interval normalization is idempotent and in range" {
  @quickcheck.check(
    (p : (Int, Int)) => {
      let i = @value.IntervalDT::new(
        p.0.to_int64() * 1000L,
        p.1.to_int64() * 1000L,
      )
      let again = @value.IntervalDT::new(i.seconds, i.nanos.to_int64())
      again == i &&
      i.nanos >= 0 &&
      i.nanos <= 999999999 &&
      i.hours() < 24L &&
      i.minutes() < 60L &&
      i.seconds_part() < 60L
    },
    count=200,
  )
}

///|
test "legacy and new $time forms decode alike" {
  @quickcheck.check(
    (a : @arbitrary.ArbTimestamp) => {
      let t = a.value.time
      guard t.precision == 0 else { return true }
      let text = "\{pad2(t.hour)}:\{pad2(t.minute)}:\{pad2(t.second)}"
      let legacy = @partiql_ion.from_ion(
        @ion_core.IonValue::string(text).with_annotation(
          @ion_core.SymbolToken::new("$time"),
        ),
      )
      let plain = @value.Time::new(
        hour=t.hour,
        minute=t.minute,
        second=t.second,
      )
      legacy == @value.Value::Time(plain)
    },
    count=200,
  )
}

///|
fn pad2(n : Int) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
test "time zone presence breaks ties: without time zone sorts first" {
  @quickcheck.check(
    (a : @arbitrary.ArbTimestamp) => {
      let t = a.value.time
      let with_zone = (offset : Int?) => {
        @value.Value::Timestamp(
          @value.Timestamp::new(
            a.value.date,
            @value.Time::new(
              hour=t.hour,
              minute=t.minute,
              second=t.second,
              nanos=t.nanos,
              precision=t.precision,
              offset~,
            ),
          ),
        )
      }
      let local_ts = with_zone(None)
      let utc = with_zone(Some(0))
      @value.compare(local_ts, utc, nulls=NullsFirst) == -1 &&
      @value.compare(utc, local_ts, nulls=NullsFirst) == 1 &&
      !@value.eqg(local_ts, utc)
    },
    count=200,
  )
}
