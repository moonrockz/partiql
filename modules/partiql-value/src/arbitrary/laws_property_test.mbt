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

///|
test "Tuple::new: dropping MISSING first gives an equal tuple" {
  @quickcheck.check(
    (t : (@arbitrary.ArbValue, @arbitrary.ArbValue, @arbitrary.ArbValue)) => {
      let pairs = [("a", v(t.0)), ("b", v(t.1)), ("a", v(t.2))]
      let kept = pairs.filter(pair => !(pair.1 is Missing))
      @value.Tuple::new(pairs) == @value.Tuple::new(kept)
    },
    count=200,
  )
}

///|
test "a value is eqg-equal to its lowered form" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      v(a).is_absent() || @value.eqg(v(a), v(a).lower_deep())
    },
    count=200,
  )
}

///|
test "big integers equal their decimal and float forms" {
  @quickcheck.check(
    (m : Int) => {
      let k = (m % 1000 + 1000) % 1000 + 1
      let two64 = @bigint.BigInt::from_string("18446744073709551616")
      let big = two64 * @bigint.BigInt::from_int(k)
      let values : Array[@value.Value] = [
        @value.Value::integer(big),
        @value.Value::Decimal(@ion_core.Decimal::new(big * 100N, -2)),
        @value.Value::Float(18446744073709551616.0 * k.to_double()),
      ]
      values[0] is BigInt(_) &&
      values.iter().all(x => values.iter().all(y => @value.eqg(x, y)))
    },
    count=200,
  )
}

///|
test "Value::integer returns Int exactly when the value fits in Int64" {
  @quickcheck.check(
    (p : (Int64, Int)) => {
      let n = p.0
      let fits = @value.Value::integer(@bigint.BigInt::from_int64(n)) ==
        @value.Value::Int(n)
      let beyond = @bigint.BigInt::from_int64(9223372036854775807L) +
        @bigint.BigInt::from_int((p.1 % 1000 + 1000) % 1000 + 1)
      fits &&
      @value.Value::integer(beyond) is BigInt(_) &&
      @value.Value::integer(-beyond - 1N) is BigInt(_) &&
      @value.Value::integer(-@bigint.BigInt::from_string("9223372036854775808")) ==
      @value.Value::Int(-9223372036854775808L)
    },
    count=200,
  )
}

///|
fn leap(year : Int) -> Bool {
  if year % 400 == 0 {
    true
  } else if year % 100 == 0 {
    false
  } else {
    year % 4 == 0
  }
}

///|
fn month_days(year : Int, month : Int) -> Int {
  [31, if leap(year) { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month -
  1]
}

///|
test "Date::new accepts exactly the valid dates" {
  @quickcheck.check(
    (p : (Int, Int, Int)) => {
      let year = p.0 % 3000
      let month = p.1 % 15
      let day = p.2 % 33
      let valid = month >= 1 &&
        month <= 12 &&
        day >= 1 &&
        day <= month_days(year, month)
      let accepted = try @value.Date::new(year~, month~, day~) catch {
        _ => false
      } noraise {
        _ => true
      }
      accepted == valid
    },
    count=500,
  )
}

///|
test "Time::new accepts exactly the valid times" {
  @quickcheck.check(
    (p : (Int, Int, Int, Int)) => {
      let hour = p.0 % 26
      let minute = p.1 % 62
      let second = p.2 % 62
      let offset = p.3 % 1500
      let valid = hour >= 0 &&
        hour <= 23 &&
        minute >= 0 &&
        minute <= 59 &&
        second >= 0 &&
        second <= 59 &&
        offset >= -1439 &&
        offset <= 1439
      let accepted = try
        @value.Time::new(hour~, minute~, second~, offset=Some(offset))
      catch {
        _ => false
      } noraise {
        _ => true
      }
      accepted == valid
    },
    count=500,
  )
}

///|
test "a decoded non-normalized interval equals the normalized value" {
  @quickcheck.check(
    (p : (Int, Int, Int, Int)) => {
      let pos = (n : Int) => (n % 200 + 200) % 200
      let (d, h, m, s) = (pos(p.0), pos(p.1), pos(p.2), pos(p.3))
      let text = "$interval_dt::{days: \{d}, hours: \{h}, minutes: \{m}, seconds: \{s}, nanos: 1500000000}"
      let decoded = @partiql_ion.from_ion(@text.read_ion(text))
      let total = d.to_int64() * 86400L +
        h.to_int64() * 3600L +
        m.to_int64() * 60L +
        s.to_int64()
      decoded ==
      @value.Value::IntervalDT(@value.IntervalDT::new(total, 1500000000L))
    },
    count=200,
  )
}

///|
test "maps never hold MISSING and ignore entry order" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      match v(a) {
        Map(m) => {
          let reversed = @value.MapValue::new(
            key_type=m.key_type,
            value_type=m.value_type,
            m.entries().to_owned().rev(),
          )
          m.entries().iter().all(pair => !(pair.1 is Missing)) &&
          @value.Value::Map(reversed) == v(a)
        }
        _ => true
      }
    },
    count=200,
  )
}

///|
test "MapValue::new drops MISSING values" {
  @quickcheck.check(
    (p : (@arbitrary.ArbValue, Int)) => {
      let key = @value.Value::Int(p.1.to_int64())
      let m = @value.MapValue::new(key_type=Integer, value_type=Dynamic, [
        (key, @value.Value::Missing),
      ])
      m.length() == 0
    },
    count=50,
  )
}

///|
test "maps that differ only in one key are not equal" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      guard v(a) is Map(m) && m.length() > 0 && m.key_type == String else {
        return true
      }
      let entries = m.entries().to_owned()
      // A key that no generated string key uses.
      entries[0] = (@value.Value::String("\u{1F600}fresh"), entries[0].1)
      let changed = @value.MapValue::new(
        key_type=m.key_type,
        value_type=m.value_type,
        entries,
      )
      !@value.eqg(v(a), @value.Value::Map(changed)) &&
      @value.compare(v(a), @value.Value::Map(changed), nulls=NullsFirst) != 0
    },
    count=500,
  )
}

///|
fn rebuild(
  g : @value.GraphValue,
  nodes : Array[@value.GraphNode],
  edges : Array[@value.GraphEdge],
) -> @value.Value raise {
  ignore(g)
  @value.Value::Graph(@value.GraphValue::new(nodes, edges))
}

///|
test "graphs ignore node and edge order, and undirected end order" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      guard v(a) is Graph(g) else { return true }
      let nodes = g.nodes().to_owned()
      let edges = g.edges().to_owned()
      let swapped = edges.map(e => {
        @value.GraphEdge::new(
          id=e.id,
          labels=e.labels().to_owned().rev(),
          payload=e.payload,
          ends=match e.ends {
            Undirected(x, y) => Undirected(y, x)
            other => other
          },
        )
      })
      rebuild(g, nodes.rev(), edges.rev()) == v(a) &&
      rebuild(g, nodes, swapped) == v(a)
    },
    count=200,
  )
}

///|
test "reversing a directed edge between two nodes changes the graph" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      guard v(a) is Graph(g) else { return true }
      let edges = g.edges().to_owned()
      guard edges.search_by(e => e.ends is Directed(from~, to~) && from != to)
        is Some(k) else {
        return true
      }
      let e = edges[k]
      guard e.ends is Directed(from~, to~) else { return true }
      edges[k] = @value.GraphEdge::new(
        id=e.id,
        labels=e.labels().to_owned(),
        payload=e.payload,
        ends=Directed(from=to, to=from),
      )
      let changed = rebuild(g, g.nodes().to_owned(), edges)
      !(changed == v(a)) &&
      !@value.eqg(changed, v(a)) &&
      @value.compare(changed, v(a), nulls=NullsFirst) != 0
    },
    count=500,
  )
}

///|
test "changing one node payload changes the graph" {
  @quickcheck.check(
    (a : @arbitrary.ArbValue) => {
      guard v(a) is Graph(g) && g.nodes().length() > 0 else { return true }
      let nodes = g.nodes().to_owned()
      let n = nodes[0]
      // A payload that no generator produces.
      nodes[0] = @value.GraphNode::new(
        id=n.id,
        labels=n.labels().to_owned(),
        payload=Some(@value.Value::String("\u{1F600}fresh")),
      )
      let changed = rebuild(g, nodes, g.edges().to_owned())
      !@value.eqg(changed, v(a)) &&
      @value.compare(changed, v(a), nulls=NullsFirst) != 0
    },
    count=500,
  )
}
