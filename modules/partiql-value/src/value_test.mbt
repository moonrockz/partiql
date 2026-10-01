///|
test "NULL and MISSING are absent values" {
  @expect.expect(@value.Value::Null.is_absent()).to_be_true()
  @expect.expect(@value.Value::Missing.is_absent()).to_be_true()
}

///|
test "NULL and MISSING are different values" {
  @expect.expect(@value.Value::Null).not().to_equal(@value.Value::Missing)
}
