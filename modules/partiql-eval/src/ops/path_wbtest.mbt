///|
test "field_match counts every matching field" {
  let t = @value.Tuple::Tuple([
    ("a", @value.Value::from_int(1)),
    ("A", @value.Value::from_int(2)),
    ("a", @value.Value::from_int(3)),
  ])
  @expect.expect_all(soft => {
    soft.expect(field_match(t, "z", delimited=false)).to_equal(NoField)
    soft
    .expect(field_match(t, "A", delimited=true))
    .to_equal(One(@value.Value::from_int(2)))
    soft
    .expect(field_match(t, "a", delimited=true))
    .to_equal(Many(@value.Value::from_int(1), count=2))
    soft
    .expect(field_match(t, "A", delimited=false))
    .to_equal(Many(@value.Value::from_int(1), count=3))
  })
}
