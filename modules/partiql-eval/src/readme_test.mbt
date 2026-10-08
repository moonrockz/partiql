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
