// Test support: shapes of graph MATCH nodes (M2b plan Task 1).

///|
fn label_shape(l : @ast.Label) -> String {
  match l.kind {
    Name(i) => ident_shape(i)
    Wildcard => "%"
    Not(x) => "(! \{label_shape(x)})"
    And(a, b) => "(& \{label_shape(a)} \{label_shape(b)})"
    Or(a, b) => "(| \{label_shape(a)} \{label_shape(b)})"
  }
}

///|
/// The quantifier with a leading space, or "".
fn quantifier_shape(q : @ast.Quantifier?) -> String {
  match q {
    None => ""
    Some({ kind: Plus, .. }) => " +"
    Some({ kind: Star, .. }) => " *"
    Some({ kind: Range(lower~, upper=Some(u)), .. }) => " {\{lower},\{u}}"
    Some({ kind: Range(lower~, upper=None), .. }) => " {\{lower},}"
  }
}

///|
/// `name`, `:label`, `(where e)`, each only when present.
fn element_shape(
  variable : @ast.Identifier?,
  label : @ast.Label?,
  where_ : @ast.Expr?,
) -> Array[String] {
  let parts : Array[String] = []
  if variable is Some(v) {
    parts.push(ident_shape(v))
  }
  if label is Some(l) {
    parts.push(":\{label_shape(l)}")
  }
  if where_ is Some(w) {
    parts.push("(where \{shape(w)})")
  }
  parts
}

///|
fn direction_shape(d : @ast.EdgeDirection) -> String {
  match d {
    Left => "<-"
    Undirected => "~"
    Right => "->"
    LeftOrUndirected => "<~"
    UndirectedOrRight => "~>"
    LeftOrRight => "<->"
    Any => "-"
  }
}

///|
fn restrictor_shape(r : @ast.Restrictor) -> String {
  match r {
    Walk => "walk"
    Trail => "trail"
    Acyclic => "acyclic"
    Simple => "simple"
  }
}

///|
fn part_shape(p : @ast.PathPart) -> String {
  match p {
    Node(n) => {
      let parts = element_shape(n.variable, n.label, n.where_)
      if parts.is_empty() {
        "(node)"
      } else {
        "(node \{parts.join(" ")})"
      }
    }
    Edge(e) => {
      let filler = match e.filler {
        Some(f) =>
          " [\{element_shape(f.variable, f.label, f.where_).join(" ")}]"
        None => ""
      }
      "(edge \{direction_shape(e.direction)}\{filler}\{quantifier_shape(e.quantifier)})"
    }
    Group(g) => {
      let delimiter = match g.delimiter {
        Paren => "paren"
        Bracket => "bracket"
      }
      let where_ = match g.where_ {
        Some(w) => " (where \{shape(w)})"
        None => ""
      }
      "(group \{delimiter} \{path_shape(g.path)}\{where_}\{quantifier_shape(g.quantifier)})"
    }
  }
}

///|
fn path_shape(p : @ast.PathPattern) -> String {
  let parts : Array[String] = []
  if p.restrictor is Some(r) {
    parts.push(restrictor_shape(r))
  }
  if p.variable is Some(v) {
    parts.push("\{ident_shape(v)} =")
  }
  for part in p.parts {
    parts.push(part_shape(part))
  }
  "(path \{parts.join(" ")})"
}

///|
fn selector_shape(s : @ast.Selector) -> String {
  match s.kind {
    AnyShortest => "any-shortest"
    AllShortest => "all-shortest"
    Shortest => "shortest"
    Any(k=None) => "any"
    Any(k=Some(k)) => "(any \{k})"
    ShortestK(k~, group~) =>
      if group {
        "(shortest \{k} group)"
      } else {
        "(shortest \{k})"
      }
  }
}

///|
fn graph_shape(m : @ast.GraphMatch) -> String {
  let parts = [shape(m.graph)]
  if m.pattern.selector is Some(s) {
    parts.push(selector_shape(s))
  }
  for p in m.pattern.paths {
    parts.push(path_shape(p))
  }
  if m.pattern.where_ is Some(w) {
    parts.push("(where \{shape(w)})")
  }
  "(match \{parts.join(" ")})"
}
