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
test "CAST to groups of later tasks is unsupported for now" {
  // Pins the intermediate state. Each later task deletes its line: Task 4
  // STRING, Task 6 DATE, Task 7 INTERVAL; Task 8 deletes the test.
  @expect.expect_all(soft => {
    soft.expect(failure_of("CAST([1] AS BAG)")).to_equal("unsupported")
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
