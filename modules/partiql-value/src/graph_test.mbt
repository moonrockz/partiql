///|
fn node(
  id : String,
  labels? : Array[String] = [],
  payload? : @value.Value? = None,
) -> @value.GraphNode {
  @value.GraphNode::new(id~, labels~, payload~)
}

///|
fn edge(
  id : String,
  ends : @value.Ends,
  labels? : Array[String] = [],
  payload? : @value.Value? = None,
) -> @value.GraphEdge {
  @value.GraphEdge::new(id~, ends~, labels~, payload~)
}

///|
fn graph(
  nodes : Array[@value.GraphNode],
  edges : Array[@value.GraphEdge],
) -> @value.Value raise {
  @value.Value::Graph(@value.GraphValue::new(nodes, edges))
}

///|
test "graph constructor rules" {
  @expect.expect_all(soft => {
    soft
    .expect_call(() => graph([node("n1"), node("n1")], []))
    .to_raise_matching(
      e => e is @value.GraphError::DuplicateNodeId(_),
      description="DuplicateNodeId",
    )
    soft
    .expect_call(() => {
      graph([node("n1")], [
        edge("e1", Directed(from="n1", to="n1")),
        edge("e1", Undirected("n1", "n1")),
      ])
    })
    .to_raise_matching(
      e => e is @value.GraphError::DuplicateEdgeId(_),
      description="DuplicateEdgeId",
    )
    soft
    .expect_call(() => {
      graph([node("n1")], [edge("e1", Directed(from="n1", to="n2"))])
    })
    .to_raise_matching(
      e => e is @value.GraphError::UnknownNode(_),
      description="UnknownNode",
    )
    soft
    .expect_call(() => {
      graph([node("n1", payload=Some(@value.Value::Missing))], [])
    })
    .to_raise_matching(
      e => e is @value.GraphError::MissingPayload(_),
      description="MissingPayload",
    )
    // Node and edge ids are separate namespaces.
    soft
    .expect_call(() => graph([node("x")], [edge("x", Undirected("x", "x"))]))
    .not()
    .to_raise()
  })
}

///|
test "graph labels are de-duplicated" {
  match graph([node("n1", labels=["a", "b", "a"])], []) {
    Graph(g) => @expect.expect(g.nodes()[0].labels).to_equal(["a", "b"])
    other => fail("unexpected \{@debug.to_string(other)}")
  }
}

///|
test "graph identity is id-based and order-insensitive" {
  let a = graph([node("n1", labels=["x", "y"]), node("n2")], [
    edge("e1", Undirected("n1", "n2")),
    edge("e2", Directed(from="n1", to="n2")),
  ])
  let b = graph([node("n2"), node("n1", labels=["y", "x"])], [
    edge("e2", Directed(from="n1", to="n2")),
    edge("e1", Undirected("n2", "n1")),
  ])
  let reversed = graph([node("n1", labels=["x", "y"]), node("n2")], [
    edge("e1", Undirected("n1", "n2")),
    edge("e2", Directed(from="n2", to="n1")),
  ])
  let null_payload = graph([node("n1", payload=Some(@value.Value::Null))], [])
  let no_payload = graph([node("n1")], [])
  @expect.expect_all(soft => {
    soft.expect(a == b).to_be_true()
    soft.expect(a == reversed).to_be_false()
    soft.expect(null_payload == no_payload).to_be_false()
  })
}
