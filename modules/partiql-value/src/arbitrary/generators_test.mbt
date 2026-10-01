///|
/// Every value inside `v`, including `v`, in depth-first order.
fn all_values(v : @value.Value) -> Array[@value.Value] {
  let out = [v]
  match v {
    List(items) =>
      for item in items {
        out.append(all_values(item))
      }
    Bag(b) =>
      for item in b.items() {
        out.append(all_values(item))
      }
    Tuple(t) =>
      for pair in t.fields() {
        out.append(all_values(pair.1))
      }
    Map(m) =>
      for pair in m.entries() {
        out.append(all_values(pair.0))
        out.append(all_values(pair.1))
      }
    _ => ()
  }
  out
}

///|
test "generators cover the edge cases" {
  let rs = @splitmix.new(seed=42UL)
  let mut nan = false
  let mut big = false
  let mut missing_in_bag = false
  let mut ion = false
  let mut map = false
  let mut zoned = false
  let mut local_ts = false
  for _ in 0..<2000 {
    for v in all_values(@arbitrary.gen_value(6, rs)) {
      match v {
        Float(d) if d.is_nan() => nan = true
        BigInt(_) => big = true
        Bag(b) if b.items().iter().any((x : @value.Value) => x is Missing) =>
          missing_in_bag = true
        Ion(_) => ion = true
        Map(m) if m.length() > 0 => map = true
        Timestamp(t) =>
          if t.time.offset is Some(_) {
            zoned = true
          } else {
            local_ts = true
          }
        _ => ()
      }
    }
  }
  @expect.expect_all(soft => {
    soft.expect(nan, label="NaN").to_be_true()
    soft.expect(big, label="BigInt").to_be_true()
    soft.expect(missing_in_bag, label="MISSING in a bag").to_be_true()
    soft.expect(ion, label="Ion").to_be_true()
    soft.expect(map, label="non-empty MAP").to_be_true()
    soft.expect(zoned, label="timestamp with time zone").to_be_true()
    soft.expect(local_ts, label="timestamp without time zone").to_be_true()
  })
}
