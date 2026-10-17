///|
test "Ion encoding handles 100000 nested lists in both modes" {
  let mut v : @value.Value = Ion(@ion_core.IonValue::int(1))
  for _ in 0..<100000 {
    v = List([v])
  }
  @expect.expect_all(soft => {
    for encoded in [@partiql_ion.to_ion(v), @partiql_ion.to_ion_data(v)] {
      let mut x = encoded
      let mut depth = 0
      while x.kind() is List([child]) {
        x = child
        depth += 1
      }
      soft.expect(depth).to_equal(100000)
      soft.expect(x.kind() is Int(n) && n == 1N).to_be_true()
    }
  })
}

///|
test "the encoded result round-trips at 100000 levels" {
  let mut v : @value.Value = Int(1)
  for _ in 0..<100000 {
    v = List([v])
  }
  @expect.expect(@partiql_ion.from_ion(@partiql_ion.to_ion(v)) == v).to_be_true()
}

///|
test "mixed containers and graph payloads round-trip at 100000 levels" {
  let mut v : @value.Value = Int(1)
  for i in 0..<100000 {
    v = match i % 6 {
      0 => List([v])
      1 => Bag(@value.Bag::new([v]))
      2 => Tuple(@value.Tuple::new([("a", v)]))
      3 =>
        Map(
          @value.MapValue::new(key_type=String, value_type=Dynamic, [
            (String("k"), v),
          ]),
        )
      4 =>
        Graph(
          @value.GraphValue::new(
            [@value.GraphNode::new(id="n", payload=Some(v))],
            [],
          ),
        )
      _ =>
        Graph(
          @value.GraphValue::new([@value.GraphNode::new(id="n")], [
            @value.GraphEdge::new(
              id="e",
              ends=Directed(from="n", to="n"),
              payload=Some(v),
            ),
          ]),
        )
    }
  }
  @expect.expect_all(soft => {
    soft.expect(@partiql_ion.from_ion(@partiql_ion.to_ion(v)) == v).to_be_true()
    soft
    .expect(@partiql_ion.from_ion(@partiql_ion.to_ion_data(v)) == v)
    .to_be_true()
  })
}
