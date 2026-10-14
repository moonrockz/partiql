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
