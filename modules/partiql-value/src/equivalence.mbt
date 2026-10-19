///|
priv enum EqualityStep {
  Pair(Value, Value)
  All(Array[Value], Array[Value], Int32)
  Search(Array[Array[Value]], Array[Array[Value]], Array[Bool], Int32, Int32)
  Matched(Array[Array[Value]], Array[Array[Value]], Array[Bool], Int32, Int32)
}

///|
fn rows(v : Value) -> Array[Array[Value]] {
  match v {
    Bag(b) => b.items().map(x => [x])
    Tuple(t) => t.fields().map(p => [Value::from_string(p.0), p.1])
    Map(m) => m.entries().map(p => [p.0, p.1])
    _ => []
  }
}

///|
/// Graph metadata is compared by id; payloads join the same explicit stack
/// as every other child. An absent payload differs from a NULL payload.
fn graph_pairs(a : GraphValue, b : GraphValue) -> (Array[Value], Array[Value])? {
  if a.nodes.length() != b.nodes.length() ||
    a.edges.length() != b.edges.length() {
    return None
  }
  let xs = []
  let ys = []
  fn payload(x : Value?, y : Value?) -> Bool {
    match (x, y) {
      (None, None) => true
      (Some(p), Some(q)) => {
        xs.push(p)
        ys.push(q)
        true
      }
      _ => false
    }
  }
  for n in a.nodes {
    guard b.nodes.search_by(m => m.id == n.id) is Some(i) else { return None }
    let m = b.nodes[i]
    if !same_label_set(n.labels, m.labels) || !payload(n.payload, m.payload) {
      return None
    }
  }
  for e in a.edges {
    guard b.edges.search_by(f => f.id == e.id) is Some(i) else { return None }
    let f = b.edges[i]
    if !same_label_set(e.labels, f.labels) ||
      e.ends != f.ends ||
      !payload(e.payload, f.payload) {
      return None
    }
  }
  Some((xs, ys))
}

///|
/// The callback can decide a node comparison after shallow lowering.
/// Returning None uses grouping equivalence for scalars and descends into
/// collections, maps and graph payloads. It must define an equivalence
/// relation, because unordered collections use one-to-one greedy matching.
pub fn equivalent_by(
  a : Value,
  b : Value,
  decide : (Value, Value) -> Bool?,
) -> Bool {
  equal_values(a, b, identity=false, decide~)
}

///|
fn equal_values(
  a : Value,
  b : Value,
  identity~ : Bool,
  decide~ : (Value, Value) -> Bool? = (_, _) => None,
) -> Bool {
  let work = [EqualityStep::Pair(a, b)]
  let mut equal = true
  while work.pop() is Some(step) {
    match step {
      All(xs, ys, i) =>
        if equal && i < xs.length() {
          work.push(All(xs, ys, i + 1))
          work.push(Pair(xs[i], ys[i]))
        }
      Search(xs, ys, used, i, j) => {
        let mut next = j
        while next < ys.length() && used[next] {
          next += 1
        }
        if next == ys.length() {
          equal = false
        } else {
          equal = true
          work.push(Matched(xs, ys, used, i, next))
          work.push(All(xs[i], ys[next], 0))
        }
      }
      Matched(xs, ys, used, i, j) =>
        if equal {
          used[j] = true
          if i + 1 < xs.length() {
            work.push(Search(xs, ys, used, i + 1, 0))
          }
        } else {
          work.push(Search(xs, ys, used, i, j + 1))
        }
      Pair(a, b) => {
        let x = if identity { a } else { lowered_or_self(a) }
        let y = if identity { b } else { lowered_or_self(b) }
        if !identity && decide(x, y) is Some(result) {
          equal = result
          continue
        }
        match (x, y) {
          (List(xs), List(ys)) => {
            equal = xs.length() == ys.length()
            if equal {
              work.push(All(xs, ys, 0))
            }
          }
          (Bag(_), Bag(_)) | (Tuple(_), Tuple(_)) | (Map(_), Map(_)) => {
            if identity &&
              x is Map(p) &&
              y is Map(q) &&
              (p.key_type != q.key_type || p.value_type != q.value_type) {
              equal = false
              continue
            }
            let xs = rows(x)
            let ys = rows(y)
            equal = xs.length() == ys.length()
            if equal && !xs.is_empty() {
              work.push(Search(xs, ys, Array::make(ys.length(), false), 0, 0))
            }
          }
          (Graph(p), Graph(q)) =>
            match graph_pairs(p, q) {
              None => equal = false
              Some((xs, ys)) => {
                equal = true
                work.push(All(xs, ys, 0))
              }
            }
          (Ion(p), Ion(q)) if identity => {
            if p.annotations().length() != q.annotations().length() ||
              !p
              .annotations()
              .iter()
              .zip(q.annotations().iter())
              .all(pair => pair.0.equivalent(pair.1)) {
              equal = false
              continue
            }
            match (p.kind(), q.kind()) {
              (List(xs), List(ys)) | (Sexp(xs), Sexp(ys)) => {
                equal = xs.length() == ys.length()
                if equal {
                  work.push(
                    All(
                      xs.map(v => Value::from_ion(v)),
                      ys.map(v => Value::from_ion(v)),
                      0,
                    ),
                  )
                }
              }
              (Struct(xs), Struct(ys)) => {
                equal = xs.length() == ys.length()
                if equal && !xs.is_empty() {
                  let row = (f : @ion_core.Field) => {
                    [
                      Value::from_ion(
                        @ion_core.IonValue::symbol_token(f.name()),
                      ),
                      Value::from_ion(f.value()),
                    ]
                  }
                  work.push(
                    Search(
                      xs.map(row),
                      ys.map(row),
                      Array::make(ys.length(), false),
                      0,
                      0,
                    ),
                  )
                }
              }
              _ => equal = p.equals(q)
            }
          }
          _ =>
            equal = if identity {
              identical_scalar(x, y)
            } else {
              grouping_scalar(x, y)
            }
        }
      }
    }
  }
  equal
}
