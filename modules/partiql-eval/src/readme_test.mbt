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
