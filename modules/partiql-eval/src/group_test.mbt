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
    // Review focus 2: after grouping, a non-key FROM variable outside an
    // aggregate is out of scope. Like any undefined name in a query, it is
    // MISSING in permissive mode and a TypeError in strict mode
    // (partiql-tests group-by.ion "... - fail" cases).
    soft
    .expect(ev("SELECT t.b FROM [{'a': 1, 'b': 2}] AS t GROUP BY t.a"))
    .to_equal(bag_of([tuple([])]))
    soft
    .expect(
      ev(
        "SELECT k FROM [{'a': 1, 'b': 2}] AS t GROUP BY t.a AS k HAVING t.b > 0",
      ),
    )
    .to_equal(bag_of([]))
    for
      text in [
        "SELECT t.b FROM [{'a': 1, 'b': 2}] AS t GROUP BY t.a", "SELECT k FROM [{'a': 1, 'b': 2}] AS t GROUP BY t.a AS k HAVING t.b > 0",
        "SELECT k FROM [{'a': 1}] AS t GROUP BY t.a AS k ORDER BY s.a",
      ] {
      soft
      .expect_call(() => ev(text, mode=Strict))
      .to_raise_matching(
        e => e is @eval.EvalError::TypeError(..),
        description="TypeError for \{text}",
      )
    }
    soft
    .expect(
      ev(
        "SELECT T.a, MAX(b) FROM <<{'a': 1, 'b': 2}, {'a': 3, 'b': 5}>> T GROUP BY T.a ORDER BY S.a",
      ),
    )
    .to_equal(
      List([
        tuple([("a", Int(1)), ("_1", Int(2))]),
        tuple([("a", Int(3)), ("_1", Int(5))]),
      ]),
    )
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

///|
test "a repeated GROUP BY expression is its key variable" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev("SELECT t.A, MAX(T.b) FROM [{'a': 1, 'b': 2}] AS t GROUP BY T.a"),
    )
    .to_equal(bag_of([tuple([("A", Int(1)), ("_1", Int(2))])]))
    soft
    .expect(
      ev("SELECT t.a + 1 AS n FROM [{'a': 1}, {'a': 1}] AS t GROUP BY t.a + 1"),
    )
    .to_equal(bag_of([tuple([("n", Int(2))])]))
    soft
    .expect(ev("SELECT t.a + 1 + 1 AS n FROM [{'a': 1}] AS t GROUP BY t.a + 1"))
    .to_equal(bag_of([tuple([("n", Int(3))])]))
    soft
    .expect(ev("SELECT s.rep, SUM(s.n) AS t FROM \{sales} AS s GROUP BY s.rep"))
    .to_equal(
      bag_of([
        tuple([("rep", String("a")), ("t", Int(30))]),
        tuple([("rep", String("b")), ("t", Int(5))]),
      ]),
    )
    // With one FROM variable, `a` and `T.a` name the same attribute.
    soft
    .expect(
      ev(
        "SELECT T.a, MAX(b) FROM <<{'a': 1, 'b': 2}, {'a': 3, 'b': 5}>> T GROUP BY a ORDER BY a DESC",
      ),
    )
    .to_equal(
      List([
        tuple([("a", Int(3)), ("_1", Int(5))]),
        tuple([("a", Int(1)), ("_1", Int(2))]),
      ]),
    )
    soft
    .expect(ev("SELECT a FROM <<{'a': 1}>> AS t GROUP BY t.a AS k"))
    .to_equal(bag_of([tuple([("a", Int(1))])]))
    soft
    .expect(ev("SELECT VALUE a FROM [{'a': 1}, {'a': 2}] GROUP BY a"))
    .to_equal(bag_of([Int(1), Int(2)]))
  })
}

///|
test "GROUP BY can name a SELECT alias" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev(
        "SELECT t.a * 10 AS tag, COUNT(*) AS c FROM [{'a': 1}, {'a': 1}, {'a': 2}] AS t GROUP BY tag",
      ),
    )
    .to_equal(
      bag_of([
        tuple([("tag", Int(10)), ("c", Int(2))]),
        tuple([("tag", Int(20)), ("c", Int(1))]),
      ]),
    )
    // A FROM variable wins over a SELECT alias.
    soft
    .expect(ev("SELECT 0 AS t, COUNT(*) AS c FROM [1, 1, 2] AS t GROUP BY t"))
    .to_equal(
      bag_of([
        tuple([("t", Int(0)), ("c", Int(2))]),
        tuple([("t", Int(0)), ("c", Int(1))]),
      ]),
    )
    // A SELECT alias wins over an implicit attribute (spec M4c §3.5):
    // here the key is COUNT(*), an aggregate in GROUP BY.
    soft
    .expect_call(() => ev("SELECT COUNT(*) AS a FROM [{'a': 1}] GROUP BY a"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
  })
}

///|
test "ORDER BY in a grouped query" {
  let rows = "[{'s': 1, 'n': 5}, {'s': 2, 'n': 1}, {'s': 1, 'n': 7}, {'s': 3, 'n': 2}]"
  @expect.expect_all(soft => {
    soft
    .expect(
      ev("SELECT s, MAX(n) AS m FROM \{rows} GROUP BY s ORDER BY MAX(n) DESC"),
    )
    .to_equal(
      List([
        tuple([("s", Int(1)), ("m", Int(7))]),
        tuple([("s", Int(3)), ("m", Int(2))]),
        tuple([("s", Int(2)), ("m", Int(1))]),
      ]),
    )
    soft
    .expect(ev("SELECT s FROM \{rows} GROUP BY s ORDER BY COUNT(n), s"))
    .to_equal(
      List([
        tuple([("s", Int(2))]),
        tuple([("s", Int(3))]),
        tuple([("s", Int(1))]),
      ]),
    )
    // Review focus 3: the output alias wins over the key for a bare name.
    soft
    .expect(
      ev(
        "SELECT COUNT(*) AS a FROM [{'a': 1}, {'a': 1}, {'a': 2}] AS t GROUP BY t.a ORDER BY a",
      ),
    )
    .to_equal(List([tuple([("a", Int(1))]), tuple([("a", Int(2))])]))
    soft
    .expect(ev("SELECT s FROM \{rows} GROUP BY s ORDER BY s LIMIT 1 OFFSET 1"))
    .to_equal(List([tuple([("s", Int(2))])]))
  })
}

///|
test "subqueries and grouped queries in other positions" {
  @expect.expect_all(soft => {
    // Review focus 4: a subquery that reads GROUP AS, and one with its own
    // aggregate.
    soft
    .expect(
      ev(
        "SELECT k, (SELECT VALUE v.t.b FROM g AS v) AS bs FROM [{'a': 1, 'b': 2}, {'a': 1, 'b': 3}] AS t GROUP BY t.a AS k GROUP AS g",
      ),
    )
    .to_equal(
      bag_of([tuple([("k", Int(1)), ("bs", bag_of([Int(2), Int(3)]))])]),
    )
    soft
    .expect(
      ev(
        "SELECT VALUE (SELECT VALUE SUM(o) FROM [1, 2] AS i) FROM [10, 20] AS o",
      ),
    )
    .to_equal(bag_of([bag_of([Int(20)]), bag_of([Int(40)])]))
    // Review focus 5: grouped queries in a set operation, a WITH and a FROM.
    soft
    .expect(
      ev(
        "(SELECT VALUE COUNT(*) FROM [1]) OUTER UNION ALL (SELECT VALUE COUNT(*) FROM [1, 2])",
      ),
    )
    .to_equal(bag_of([Int(1), Int(2)]))
    soft
    .expect(
      ev(
        "WITH c AS (SELECT VALUE COUNT(*) FROM [1, 2]) SELECT VALUE x FROM c AS x",
      ),
    )
    .to_equal(bag_of([Int(2)]))
    soft
    .expect(
      ev("SELECT VALUE x FROM (SELECT VALUE SUM(y) FROM [1, 2] AS y) AS x"),
    )
    .to_equal(bag_of([Int(3)]))
  })
}
