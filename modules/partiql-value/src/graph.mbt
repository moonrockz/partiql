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
} derive(Debug)

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
pub fn GraphNode::new(
  id~ : String,
  labels? : Array[String] = [],
  payload? : Value? = None,
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
} derive(Debug)

///|
pub fn GraphEdge::new(
  id~ : String,
  ends~ : Ends,
  labels? : Array[String] = [],
  payload? : Value? = None,
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
} derive(Debug)

///|
pub fn GraphValue::new(
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
pub fn GraphValue::nodes(self : GraphValue) -> ArrayView[GraphNode] {
  self.nodes[:]
}

///|
pub fn GraphValue::edges(self : GraphValue) -> ArrayView[GraphEdge] {
  self.edges[:]
}

///|
fn same_label_set(a : Array[String], b : Array[String]) -> Bool {
  // Labels are de-duplicated on construction, so equal sizes and inclusion
  // mean equal sets.
  a.length() == b.length() && a.iter().all(label => b.contains(label))
}

///|
fn same_payload(a : Value?, b : Value?, same : (Value, Value) -> Bool) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => same(x, y)
    _ => false
  }
}

///|
/// Id-based graph comparison: the same node and edge ids, and per id the
/// same label set, ends and payload (payloads compared with `same`).
fn same_graph(
  a : GraphValue,
  b : GraphValue,
  same : (Value, Value) -> Bool,
) -> Bool {
  if a.nodes.length() != b.nodes.length() ||
    a.edges.length() != b.edges.length() {
    return false
  }
  for n in a.nodes {
    guard b.nodes.search_by(m => m.id == n.id) is Some(k) else { return false }
    let m = b.nodes[k]
    if !same_label_set(n.labels, m.labels) ||
      !same_payload(n.payload, m.payload, same) {
      return false
    }
  }
  for e in a.edges {
    guard b.edges.search_by(f => f.id == e.id) is Some(k) else { return false }
    let f = b.edges[k]
    if !same_label_set(e.labels, f.labels) ||
      !(e.ends == f.ends) ||
      !same_payload(e.payload, f.payload, same) {
      return false
    }
  }
  true
}
