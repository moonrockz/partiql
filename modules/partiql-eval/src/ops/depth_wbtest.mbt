///|
test "SQL equality handles 100000 nested collections" {
  let mut a : @value.Value = Null
  let mut b : @value.Value = Missing
  for _ in 0..<100000 {
    a = @value.Value::from_list([a])
    b = @value.Value::from_list([b])
  }
  @expect.expect(equal(a, b) is Bool(true)).to_be_true()
}
