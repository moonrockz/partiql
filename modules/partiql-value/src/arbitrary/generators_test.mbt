///|
test "generators cover the edge cases" {
  let rs = @splitmix.new(seed=42UL)
  let mut nan = false
  let mut big = false
  let mut missing_in_bag = false
  let mut ion = false
  let mut zoned_and_local = (false, false)
  for _ in 0..<2000 {
    let v = @arbitrary.gen_value(6, rs)
    match v {
      Float(d) if d.is_nan() => nan = true
      BigInt(_) => big = true
      Bag(b) if b.items().iter().any((x : @value.Value) => x is Missing) =>
        missing_in_bag = true
      Ion(_) => ion = true
      Timestamp(t) =>
        zoned_and_local = if t.time.offset is Some(_) {
          (true, zoned_and_local.1)
        } else {
          (zoned_and_local.0, true)
        }
      _ => ()
    }
  }
  @expect.expect([
    nan,
    big,
    missing_in_bag,
    ion,
    zoned_and_local.0,
    zoned_and_local.1,
  ]).to_equal([true, true, true, true, true, true])
}
