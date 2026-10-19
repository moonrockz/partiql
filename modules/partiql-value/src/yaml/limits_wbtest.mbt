///|
test "expanded YAML budgets count keys and decoded UTF-8 payload" {
  @expect.expect_all(soft => {
    soft
    .expect(read_limited("[a, b]", max_nodes=3, max_payload=2).length())
    .to_equal(1)
    soft
    .expect_call(() => read_limited("[a, b]", max_nodes=2, max_payload=2))
    .to_raise_matching(
      e => e is YamlError(kind=Limit, ..),
      description="node budget",
    )
    soft
    .expect(read_limited("é: 😀", max_nodes=3, max_payload=6).length())
    .to_equal(1)
    soft
    .expect_call(() => read_limited("é: 😀", max_nodes=3, max_payload=5))
    .to_raise_matching(
      e => e is YamlError(kind=Limit, ..),
      description="payload budget",
    )
    soft
    .expect_call(() => read_limited("'abcdef'", max_nodes=3, max_payload=5))
    .to_raise_matching(
      e => e is YamlError(kind=Limit, ..),
      description="scanner payload budget",
    )
  })
}

///|
test "alias budgets include copies of keys and values before allocation" {
  @expect.expect_all(soft => {
    soft
    .expect(
      read_limited("[&a {é: 😀}, *a]", max_nodes=7, max_payload=12).length(),
    )
    .to_equal(1)
    soft
    .expect_call(() => {
      read_limited("[&a {é: 😀}, *a]", max_nodes=6, max_payload=12)
    })
    .to_raise_matching(
      e => e is YamlError(kind=Limit, ..),
      description="aliased key nodes",
    )
    soft
    .expect_call(() => {
      read_limited("[&a {é: 😀}, *a]", max_nodes=7, max_payload=11)
    })
    .to_raise_matching(
      e => e is YamlError(kind=Limit, ..),
      description="aliased key payload",
    )
    let fanout = "[&a [x, x], &b [*a, *a], &c [*b, *b], *c]"
    soft
    .expect_call(() => read_limited(fanout, max_nodes=32, max_payload=100))
    .to_raise_matching(
      e => e is YamlError(kind=Limit, ..),
      description="exponential fanout",
    )
    soft
    .expect_call(() => {
      read_limited("--- abc\n--- def", max_nodes=10, max_payload=5)
    })
    .to_raise_matching(
      e => e is YamlError(kind=Limit, ..),
      description="stream payload",
    )
    soft
    .expect_call(() => read_limited("--- 1\n--- 2", max_nodes=1, max_payload=5))
    .to_raise_matching(
      e => e is YamlError(kind=Limit, ..),
      description="stream nodes",
    )
  })
}
