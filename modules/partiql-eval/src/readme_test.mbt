///|
/// Mirrors the query example of README.mbt.md. Keep the two in step.
test "README query example" {
  let value = @eval.evaluate_text(
    "SELECT VALUE x * 10 FROM [1, 2, 3] AS x WHERE x > 1",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value).to_equal(
    @value.Value::Bag(@value.Bag::new([Int(20), Int(30)])),
  )
}

///|
/// Mirrors the ORDER BY example of README.mbt.md. Keep the two in step.
test "README ORDER BY example" {
  let value = @eval.evaluate_text(
    "SELECT VALUE x FROM [3, 1, 2] AS x ORDER BY x DESC LIMIT 2",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value).to_equal(@value.Value::List([Int(3), Int(2)]))
}

///|
/// Mirrors the GROUP BY example of README.mbt.md. Keep the two in step.
test "README GROUP BY example" {
  let value = @eval.evaluate_text(
    "SELECT r, SUM(s.n) AS total FROM [{'r': 'a', 'n': 1}, {'r': 'a', 'n': 2}] AS s GROUP BY s.r AS r",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value).to_equal(
    @value.Value::Bag(
      @value.Bag::new([
        Tuple(@value.Tuple::new([("r", String("a")), ("total", Int(3))])),
      ]),
    ),
  )
}

///|
/// Mirrors the function example of README.mbt.md. Keep the two in step.
test "README function example" {
  let value = @eval.evaluate_text(
    "UPPER(TRIM('  straße  '))",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value).to_equal(@value.Value::String("STRASSE"))
}

///|
/// Mirrors the CAST example of README.mbt.md. Keep the two in step.
test "README CAST example" {
  let value = @eval.evaluate_text(
    "CAST('3.14159' AS DECIMAL(4, 2))",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value).to_equal(
    @value.Value::Decimal(@ion.Decimal::parse("3.14")),
  )
}

///|
/// Mirrors the datetime example of README.mbt.md. Keep the two in step.
test "README datetime example" {
  let value = @eval.evaluate_text(
    "TO_STRING(DATE_ADD(day, 30, DATE '2024-02-15'), 'MMMM d, yyyy')",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value).to_equal(@value.Value::String("March 16, 2024"))
}

///|
/// Mirrors the clock example of README.mbt.md. Keep the two in step.
test "README clock example" {
  let clock = @eval.Clock::fixed(@time.date_time(2026, 10, 16, hour=9))
  let value = @eval.evaluate_text(
    "CURRENT_DATE",
    env=@eval.Bindings::empty(),
    clock~,
  )
  @expect.expect(value).to_equal(
    @value.Value::Date(@value.Date::new(year=2026, month=10, day=16)),
  )
}

///|
/// Mirrors the Ion session example of README.mbt.md. Keep the two in step.
test "README binary Ion session example" {
  let input = @partiql_ion.write_bytes(
    @partiql_ion.read_text("{a: 2, b: $bag::[1, 3]}"),
  )
  let session = @eval.Session::new(env=@eval.Bindings::from_ion_bytes(input))
  let output = session.evaluate_ion_bytes(
    "a + 1; SELECT VALUE x * a FROM b AS x",
  )
  @expect.expect(@partiql_ion.read_bytes(output)).to_equal(
    @partiql_ion.read_text("3 $bag::[2, 6]"),
  )
}
