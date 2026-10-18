///|
test "field_match counts every matching field" {
  let t = @value.Tuple::Tuple([("a", Int(1)), ("A", Int(2)), ("a", Int(3))])
  @expect.expect_all(soft => {
    soft.expect(field_match(t, "z", delimited=false)).to_equal(NoField)
    soft.expect(field_match(t, "A", delimited=true)).to_equal(One(Int(2)))
    soft
    .expect(field_match(t, "a", delimited=true))
    .to_equal(Many(Int(1), count=2))
    soft
    .expect(field_match(t, "A", delimited=false))
    .to_equal(Many(Int(1), count=3))
  })
}
