///|
/// How `source` ends: "ok", or the class of its error.
fn failure_of(source : String, mode~ : @eval.Mode = Permissive) -> String {
  try ev(source, mode~) catch {
    TypeError(..) => "type"
    DataError(..) => "data"
    Unsupported(..) => "unsupported"
    Syntax(_) => "syntax"
  } noraise {
    _ => "ok"
  }
}

///|
test "CAST to numbers evaluates" {
  @expect.expect_all(soft => {
    soft.expect(ev("CAST('12' AS INT)")).to_equal(Int(12))
    soft.expect(ev("CAST(1.5 AS INTEGER)")).to_equal(Int(2))
    soft.expect(ev("CAST(TRUE AS BIGINT)")).to_equal(Int(1))
    soft.expect(ev("CAST(5 AS DECIMAL(5, 2))")).to_equal(dec("5.00"))
    soft.expect(ev("CAST(5 AS NUMERIC(3))")).to_equal(dec("5"))
    soft.expect(ev("CAST(0 AS BOOLEAN)")).to_equal(Bool(false))
    soft.expect(ev("CAST(NULL AS INT)")).to_equal(Null)
    soft.expect(ev("CAST(MISSING AS INT)")).to_equal(Missing)
    soft.expect(ev("CAST(1 AS ANY)")).to_equal(Int(1))
    soft.expect(ev("CAST(`1.5e0` AS INT)")).to_equal(Int(2))
  })
}

///|
test "CAST failure classes in both modes" {
  @expect.expect_all(soft => {
    // Not a valid literal: MISSING in permissive, TypeError in strict.
    soft.expect(ev("CAST('hello' AS INT)")).to_equal(Missing)
    soft
    .expect(failure_of("CAST('hello' AS INT)", mode=Strict))
    .to_equal("type")
    // No cast for the kind.
    soft.expect(ev("CAST([1] AS INT)")).to_equal(Missing)
    soft.expect(failure_of("CAST([1] AS INT)", mode=Strict)).to_equal("type")
    // Out of range: DataError in both modes.
    soft.expect(failure_of("CAST(128 AS TINYINT)")).to_equal("data")
    soft
    .expect(failure_of("CAST(128 AS TINYINT)", mode=Strict))
    .to_equal("data")
    soft.expect(failure_of("CAST('2e10' AS INT)")).to_equal("data")
  })
}

///|
test "CAST target checks are static" {
  @expect.expect_all(soft => {
    for
      source in [
        "CAST(1 AS NULL)", "CAST(1 AS MISSING)", "CAST(1 AS DECIMAL(39))", "CAST(1 AS DECIMAL(0))",
        "CAST(1 AS DECIMAL(3, 4))", "CAST('a' AS CHAR(0))", "CAST('a' AS VARCHAR(0))",
        "CAST(1 AS FLOAT(54))", "CAST(1 AS FLOAT(0))", "CAST(TIME '12:00:00' AS TIME(10))",
        "CAST(1 AS INTERVAL MONTH TO YEAR)", "CAST(1 AS no_such_type)",
        // Static: the operand is never evaluated, so even a failing one is
        // not reached.
         "CAST(1 / 0 AS NULL)",
      ] {
      soft.expect(failure_of(source)).to_equal("data")
      soft.expect(failure_of(source, mode=Strict)).to_equal("data")
    }
    for
      source in [
        "CAST([1] AS SEXP)", "CAST([1] AS ARRAY<INT>)", "CAST({} AS MAP<LIST, INT>)",
        "CAST({} AS MAP<STRING, LIST>)", "CAST({} AS MAP<DYNAMIC, INT>)",
      ] {
      soft.expect(failure_of(source)).to_equal("unsupported")
    }
  })
}

///|
test "CAST to text" {
  @expect.expect_all(soft => {
    soft.expect(ev("CAST(1.50 AS STRING)")).to_equal(String("1.50"))
    soft.expect(ev("CAST(TRUE AS VARCHAR)")).to_equal(String("TRUE"))
    soft.expect(ev("CAST('abcdef' AS VARCHAR(3))")).to_equal(String("abc"))
    soft.expect(ev("CAST('ab' AS CHAR(4))")).to_equal(String("ab  "))
    soft.expect(ev("CAST('ab' AS CHAR)")).to_equal(String("a"))
    soft.expect(ev("CAST(`abc` AS SYMBOL)")).to_equal(String("abc"))
    soft
    .expect(ev("CAST(DATE '2007-10-10' AS STRING)"))
    .to_equal(String("2007-10-10"))
    soft
    .expect(ev("CAST(TIME WITH TIME ZONE '23:12:12.1267-05:30' AS STRING)"))
    .to_equal(String("23:12:12.1267-05:30"))
    soft.expect(ev("CHAR_LENGTH(CAST('😀' AS CHAR(3)))")).to_equal(Int(3))
    soft
    .expect(failure_of("CAST(12345 AS CHAR(3))", mode=Strict))
    .to_equal("data")
    soft.expect(ev("CAST(`null.int` AS STRING)")).to_equal(Null)
  })
}

///|
test "CAST uses the session time zone" {
  guard @eval.ZoneOffset::new(330) is Some(india) else { fail("offset") }
  let source = "CAST(TIME '12:00:00' AS TIME WITH TIME ZONE)"
  let at_utc = @eval.evaluate_text(source, env=@eval.Bindings::empty())
  let at_india = @eval.evaluate_text(
    source,
    env=@eval.Bindings::empty(),
    zone=india,
  )
  @expect.expect_all(soft => {
    soft.expect(at_utc is Time({ offset: Some(0), .. })).to_be_true()
    soft.expect(at_india is Time({ offset: Some(330), .. })).to_be_true()
    soft
    .expect(ev("CAST('2020-01-01' AS DATE)"))
    .to_equal(Date(@value.Date::new(year=2020, month=1, day=1)))
    soft
    .expect(failure_of("CAST(TIME '12:00:00' AS TIMESTAMP)"))
    .to_equal("unsupported")
  })
}

///|
test "CAST to INTERVAL" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("CAST(INTERVAL '13' MONTH AS INTERVAL YEAR TO MONTH)"))
    .to_equal(ev("INTERVAL '1-1' YEAR TO MONTH"))
    soft
    .expect(ev("CAST(INTERVAL '1.123456789' SECOND AS INTERVAL SECOND(3, 3))"))
    .to_equal(ev("INTERVAL '1.123' SECOND"))
    soft
    .expect(ev("CAST(2 AS INTERVAL HOUR)"))
    .to_equal(ev("INTERVAL '2' HOUR"))
    soft
    .expect(failure_of("CAST(100 AS INTERVAL DAY)", mode=Strict))
    .to_equal("data")
  })
}

///|
test "CAST to collections and maps" {
  @expect.expect_all(soft => {
    soft.expect(ev("CAST([1, 2] AS BAG)")).to_equal(bag_of([Int(1), Int(2)]))
    soft
    .expect(ev("CAST({'a': 1, 'a': 2} AS MAP<STRING, INTEGER>)"))
    .to_equal(ev("MAP {'a': 2}"))
    soft.expect(ev("CAST({'a': 'x'} AS MAP<STRING, INT>)")).to_equal(Missing)
    soft
    .expect(failure_of("CAST({'a': 'x'} AS MAP<STRING, INT>)", mode=Strict))
    .to_equal("type")
    soft
    .expect(failure_of("CAST(MAP {'a': 300} AS MAP<STRING, TINYINT>)"))
    .to_equal("data")
    soft
    .expect(
      failure_of("CAST(MAP {'a': 300} AS MAP<STRING, TINYINT>)", mode=Strict),
    )
    .to_equal("data")
    // Elements of an Ion sexp stay Ion-boxed (shallow lowering, as for
    // paths); they equal the PartiQL values.
    soft.expect(ev("CAST(`(1 2)` AS LIST) = [1, 2]")).to_equal(Bool(true))
  })
}

///|
test "t[CAST(e AS STRING)] names a field; a map keeps its key lookup" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("{'attr': 1, 'b': 2}[CAST('at' || 'tr' AS STRING)]"))
    .to_equal(Int(1))
    soft.expect(ev("{'a': 1}[CAST('a' AS VARCHAR(3))]")).to_equal(Int(1))
    // A field name match is case-sensitive, as for a string literal.
    soft.expect(ev("{'a': 1}[CAST('A' AS STRING)]")).to_equal(Missing)
    soft.expect(ev("MAP {'k': 5}[CAST('k' AS STRING)]")).to_equal(Int(5))
    // Not a string cast: a tuple is not indexed by an expression.
    soft.expect(ev("{'a': 1}['a' || '']")).to_equal(Missing)
  })
}

///|
test "the implied name of a CAST is the name of its operand" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT CAST(t.n AS STRING) FROM [{'n': 1}] AS t"))
    .to_equal(bag_of([tuple([("n", String("1"))])]))
    soft
    .expect(
      ev(
        "SELECT num FROM [{'num': 1.0}, {'num': 1}] AS t GROUP BY CAST(t.num AS INT)",
      ),
    )
    .to_equal(bag_of([tuple([("num", Int(1))])]))
  })
}

///|
test "a MAP literal declares the types of uniform CAST keys and values" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("MAP { CAST(100 AS BIGINT): 'hundred' } IS MAP<BIGINT, STRING>"))
    .to_equal(Bool(true))
    soft
    .expect(ev("MAP { 'a': CAST(1 AS SMALLINT) } IS MAP<STRING, SMALLINT>"))
    .to_equal(Bool(true))
    // Mixed: inferred as before.
    soft
    .expect(ev("MAP { CAST(1 AS BIGINT): 'a', 2: 'b' } IS MAP<INT, STRING>"))
    .to_equal(Bool(true))
  })
}

///|
test "CHAR and VARCHAR lengths have an upper limit" {
  // CHAR(n) pads to n code points, so a huge n would allocate without bound.
  @expect.expect_all(soft => {
    soft.expect(failure_of("CAST(1 AS CHAR(2147483647))")).to_equal("data")
    soft.expect(failure_of("CAST(1 AS CHAR(10485761))")).to_equal("data")
    soft.expect(failure_of("CAST(1 AS VARCHAR(10485761))")).to_equal("data")
    soft.expect(failure_of("CAST('a' AS VARCHAR(10485760))")).to_equal("ok")
  })
}
