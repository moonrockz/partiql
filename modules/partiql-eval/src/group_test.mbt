///|
fn dec(text : String) -> @value.Value raise {
  Decimal(@ion.Decimal::parse(text))
}

///|
let sales : String =
  #|<<{'rep': 'a', 'y': 1, 'n': 10}, {'rep': 'a', 'y': 2, 'n': 20},
  #|  {'rep': 'b', 'y': 1, 'n': 5}>>

///|
test "GROUP BY with aggregates" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev(
        "SELECT rep, SUM(s.n) AS t, COUNT(*) AS c FROM \{sales} AS s GROUP BY s.rep",
      ),
    )
    .to_equal(
      bag_of([
        tuple([("rep", String("a")), ("t", Int(30)), ("c", Int(2))]),
        tuple([("rep", String("b")), ("t", Int(5)), ("c", Int(1))]),
      ]),
    )
    soft
    .expect(
      ev("SELECT r, AVG(s.n) AS a FROM \{sales} AS s GROUP BY s.rep AS r"),
    )
    .to_equal(
      bag_of([
        tuple([("r", String("a")), ("a", dec("15."))]),
        tuple([("r", String("b")), ("a", dec("5."))]),
      ]),
    )
    soft
    .expect(ev("SELECT y, MIN(n) AS lo, MAX(n) AS hi FROM \{sales} GROUP BY y"))
    .to_equal(
      bag_of([
        tuple([("y", Int(1)), ("lo", Int(5)), ("hi", Int(10))]),
        tuple([("y", Int(2)), ("lo", Int(20)), ("hi", Int(20))]),
      ]),
    )
    soft
    .expect(
      ev(
        "SELECT a, COUNT(DISTINCT t.b) AS c FROM [{'a': 1, 'b': 10}, {'a': 1, 'b': 10}, {'a': 1, 'b': 20}, {'a': 2, 'b': 10}] t GROUP BY t.a",
      ),
    )
    .to_equal(
      bag_of([
        tuple([("a", Int(1)), ("c", Int(2))]),
        tuple([("a", Int(2)), ("c", Int(1))]),
      ]),
    )
  })
}

///|
test "aggregates without GROUP BY are one group, also over empty input" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT COUNT(x), SUM(x), MIN(x), MAX(x), AVG(x) FROM []"))
    .to_equal(
      bag_of([
        tuple([
          ("_1", Int(0)),
          ("_2", Null),
          ("_3", Null),
          ("_4", Null),
          ("_5", Null),
        ]),
      ]),
    )
    soft
    .expect(ev("SELECT VALUE COUNT(*) FROM [1, 2, 3]"))
    .to_equal(bag_of([Int(3)]))
    soft
    .expect(ev("SELECT VALUE SUM(i) FROM << 0, 1 >> AS i"))
    .to_equal(bag_of([Int(1)]))
    soft.expect(ev("SELECT x FROM [] AS x GROUP BY x")).to_equal(bag_of([]))
    soft
    .expect(ev("SELECT VALUE COUNT(*) FROM [1, 2] AS x GROUP ALL"))
    .to_equal(bag_of([Int(2)]))
    soft
    .expect(ev("SELECT VALUE g FROM [] AS x GROUP ALL AS g"))
    .to_equal(bag_of([bag_of([])]))
  })
}

///|
test "GROUP AS holds the FROM and LET variables of each row" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev(
        "SELECT col1, g FROM [{'col1': 1}, {'col1': 1}] AS t GROUP BY t.col1 AS col1 GROUP AS g",
      ),
    )
    .to_equal(
      bag_of([
        tuple([
          ("col1", Int(1)),
          (
            "g",
            bag_of([
              tuple([("t", tuple([("col1", Int(1))]))]),
              tuple([("t", tuple([("col1", Int(1))]))]),
            ]),
          ),
        ]),
      ]),
    )
    soft
    .expect(
      ev(
        "SELECT VALUE g FROM [1] AS x AT i, [2] AS y LET x + y AS z GROUP ALL AS g",
      ),
    )
    .to_equal(
      bag_of([
        bag_of([
          tuple([("i", Int(0)), ("x", Int(1)), ("y", Int(2)), ("z", Int(3))]),
        ]),
      ]),
    )
    // A MISSING variable is left out of the member tuple.
    soft
    .expect(ev("SELECT VALUE g FROM [1] AS x LET MISSING AS m GROUP ALL AS g"))
    .to_equal(bag_of([bag_of([tuple([("x", Int(1))])])]))
  })
}

///|
test "NULL and MISSING keys are one group with a NULL key" {
  let rows = "[{'k': NULL, 'v': 1}, {'v': 2}, {'k': `null.int`, 'v': 4}, {'k': 1, 'v': 8}, {'k': 1.0, 'v': 16}]"
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT k, SUM(r.v) AS s FROM \{rows} AS r GROUP BY r.k AS k"))
    .to_equal(
      bag_of([
        tuple([("k", Null), ("s", Int(7))]),
        tuple([("k", Int(1)), ("s", Int(24))]),
      ]),
    )
    soft
    .expect(
      ev("SELECT someMissing FROM [1, 2] AS x GROUP BY MISSING AS someMissing"),
    )
    .to_equal(bag_of([tuple([("someMissing", Null)])]))
    // Strict mode: a path to an absent attribute fails.
    soft
    .expect_call(() => {
      ev("SELECT k FROM \{rows} AS r GROUP BY r.k AS k", mode=Strict)
    })
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}

///|
test "HAVING filters groups" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev(
        "SELECT rep FROM \{sales} AS s GROUP BY s.rep AS rep HAVING COUNT(*) > 1",
      ),
    )
    .to_equal(bag_of([tuple([("rep", String("a"))])]))
    soft
    .expect(ev("SELECT VALUE COUNT(*) FROM [1, 2] AS x HAVING SUM(x) > 5"))
    .to_equal(bag_of([]))
    soft
    .expect(ev("SELECT VALUE COUNT(*) FROM [1, 2] AS x HAVING SUM(x) > 2"))
    .to_equal(bag_of([Int(2)]))
  })
}

///|
test "SQL ANY, SOME and EVERY" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev(
        "SELECT VALUE [ANY(x), SOME(x), EVERY(x)] FROM [true, false, NULL] AS x",
      ),
    )
    .to_equal(bag_of([List([Bool(true), Bool(true), Bool(false)])]))
    soft
    .expect(ev("SELECT VALUE EVERY(x) FROM [1] AS x"))
    .to_equal(bag_of([Missing]))
  })
}

///|
test "SELECT * after grouping outputs the keys and the GROUP AS variable" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT * FROM [{'a': 1}, {'a': 1}] AS t GROUP BY t.a"))
    .to_equal(bag_of([tuple([("a", Int(1))])]))
    soft
    .expect(ev("SELECT * FROM [{'a': 1}] AS t GROUP BY t.a AS k GROUP AS g"))
    .to_equal(
      bag_of([
        tuple([
          ("k", Int(1)),
          ("g", bag_of([tuple([("t", tuple([("a", Int(1))]))])])),
        ]),
      ]),
    )
  })
}

///|
test "names after grouping: keys and GROUP AS only" {
  @expect.expect_all(soft => {
    // Review focus 2: a non-key FROM variable outside an aggregate is an
    // error in both modes, never a silent MISSING.
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect_call(() => {
        ev("SELECT t.b FROM [{'a': 1, 'b': 2}] AS t GROUP BY t.a", mode~)
      })
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError",
      )
      soft
      .expect_call(() => {
        ev(
          "SELECT k FROM [{'a': 1, 'b': 2}] AS t GROUP BY t.a AS k HAVING t.b > 0",
          mode~,
        )
      })
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError",
      )
    }
    // Inside an aggregate the FROM variables are bound per member.
    soft
    .expect(
      ev(
        "SELECT k, SUM(t.b) AS s FROM [{'a': 1, 'b': 2}] AS t GROUP BY t.a AS k",
      ),
    )
    .to_equal(bag_of([tuple([("k", Int(1)), ("s", Int(2))])]))
    // A key variable inside an aggregate is the constant of the group.
    soft
    .expect(
      ev("SELECT VALUE SUM(k) FROM [{'a': 3}, {'a': 3}] AS t GROUP BY t.a AS k"),
    )
    .to_equal(bag_of([Int(6)]))
    // An unqualified attribute inside an aggregate finds the member's tuple.
    soft
    .expect(
      ev(
        "SELECT VALUE SUM(b) FROM [{'a': 1, 'b': 2}, {'a': 1, 'b': 5}] AS t GROUP BY t.a",
      ),
    )
    .to_equal(bag_of([Int(7)]))
  })
}

///|
test "static errors of aggregates" {
  @expect.expect_all(soft => {
    for
      text in [
        "SELECT VALUE SUM(COUNT(x)) FROM [1] AS x", "SELECT VALUE x FROM [1] AS x WHERE SUM(x) > 0",
        "SELECT VALUE y FROM [1] AS x LET SUM(x) AS y", "SELECT VALUE x FROM [1] AS x GROUP BY SUM(x)",
        "SELECT VALUE x FROM (SELECT VALUE COUNT(*) FROM [1]) AS x WHERE COUNT(*) > 0",
        "SELECT VALUE SUM(x, x) FROM [1] AS x", "SELECT VALUE SUM(*) FROM [1] AS x",
        "SUM([1, 2])", "SELECT a FROM [1] AS a GROUP BY a, a", "SELECT k FROM [1] AS a GROUP BY a AS k GROUP AS k",
      ] {
      soft
      .expect_call(() => ev(text))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError for \{text}",
      )
    }
  })
}
