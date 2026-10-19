///|
/// The ends of a graph edge (RFC 0025): an ordered pair for a directed edge,
/// an unordered pair for an undirected edge. Ends name node ids.
pub(all) enum Ends {
  Directed(from~ : String, to~ : String)
  Undirected(String, String)
} derive(Debug)

///|
/// A graph node: its id from the source data, its labels (a set, kept in
/// first-seen order) and an optional payload. An absent payload is not NULL:
/// it acts as MISSING in queries.
pub struct GraphNode {
  id : String
  priv labels : Array[String]
  payload : Value?
}

///|
fn dedup_labels(labels : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for label in labels {
    if !out.contains(label) {
      out.push(label)
    }
  }
  out
}

///|
/// Build a node and remove duplicate labels in first-seen order.
/// Id uniqueness and MISSING payloads are checked when building `GraphValue`.
#alias(new, deprecated="Use GraphNode(...) instead")
pub fn GraphNode::GraphNode(
  id~ : String,
  labels~ : Array[String] = [],
  payload~ : Value? = None,
) -> GraphNode {
  { id, labels: dedup_labels(labels), payload, }
}

///|
/// A graph edge: id, labels, ends and an optional payload.
pub struct GraphEdge {
  id : String
  priv labels : Array[String]
  ends : Ends
  payload : Value?
}

///|
/// Build an edge and remove duplicate labels in first-seen order.
/// Endpoint existence, id uniqueness and MISSING payloads are checked by `GraphValue`.
#alias(new, deprecated="Use GraphEdge(...) instead")
pub fn GraphEdge::GraphEdge(
  id~ : String,
  ends~ : Ends,
  labels~ : Array[String] = [],
  payload~ : Value? = None,
) -> GraphEdge {
  { id, labels: dedup_labels(labels), ends, payload, }
}

///|
/// The labels, without duplicates, in first-seen order.
pub fn GraphNode::labels(self : GraphNode) -> ArrayView[String] {
  self.labels[:]
}

///|
/// The labels, without duplicates, in first-seen order.
pub fn GraphEdge::labels(self : GraphEdge) -> ArrayView[String] {
  self.labels[:]
}

///|
/// Why a graph could not be built.
pub(all) suberror GraphError {
  DuplicateNodeId(String)
  DuplicateEdgeId(String)
  /// An edge end that names no node.
  UnknownNode(String)
  /// A payload that is MISSING (use no payload instead).
  MissingPayload(String)
} derive(Debug, Eq)

///|
/// A PartiQL graph (RFC 0025). Node ids are unique among nodes, edge ids
/// among edges (two namespaces), and every edge end names a node.
pub struct GraphValue {
  priv nodes : Array[GraphNode]
  priv edges : Array[GraphEdge]
}

///|
/// Build a graph from copies of the node and edge arrays.
/// Raise `GraphError` for duplicate ids within either namespace, unknown
/// endpoints, or MISSING payloads. Node and edge ids may share a name.
#alias(new, deprecated="Use GraphValue(...) instead")
pub fn GraphValue::GraphValue(
  nodes : Array[GraphNode],
  edges : Array[GraphEdge],
) -> GraphValue raise GraphError {
  let node_ids : Array[String] = []
  for n in nodes {
    if node_ids.contains(n.id) {
      raise DuplicateNodeId(n.id)
    }
    if n.payload is Some(Missing) {
      raise MissingPayload(n.id)
    }
    node_ids.push(n.id)
  }
  let edge_ids : Array[String] = []
  for e in edges {
    if edge_ids.contains(e.id) {
      raise DuplicateEdgeId(e.id)
    }
    if e.payload is Some(Missing) {
      raise MissingPayload(e.id)
    }
    let (a, b) = match e.ends {
      Directed(from~, to~) => (from, to)
      Undirected(x, y) => (x, y)
    }
    for end in [a, b] {
      if !node_ids.contains(end) {
        raise UnknownNode(end)
      }
    }
    edge_ids.push(e.id)
  }
  // Copies: the caller's arrays must not change the graph.
  { nodes: nodes.copy(), edges: edges.copy(), }
}

///|
/// A read-only view of nodes in their input order.
pub fn GraphValue::nodes(self : GraphValue) -> ArrayView[GraphNode] {
  self.nodes[:]
}

///|
/// A read-only view of edges in their input order.
pub fn GraphValue::edges(self : GraphValue) -> ArrayView[GraphEdge] {
  self.edges[:]
}

///|
fn same_label_set(a : Array[String], b : Array[String]) -> Bool {
  // Labels are de-duplicated on construction, so equal sizes and inclusion
  // mean equal sets.
  a.length() == b.length() && a.iter().all(label => b.contains(label))
}
