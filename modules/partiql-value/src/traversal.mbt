///|
/// The immediate value children, in stored order: list/bag items, tuple
/// values, alternating map keys and values, then graph node/edge payloads.
/// A boxed Ion value is a leaf until explicitly lowered.
fn Value::children(self : Value) -> Array[Value] {
  match self {
    List(xs) => xs
    Bag(b) => b.items().to_owned()
    Tuple(t) => t.fields().map(p => p.1)
    Map(m) => {
      let out = []
      for (k, v) in m.entries() {
        out.push(k)
        out.push(v)
      }
      out
    }
    Graph(g) => {
      let out = []
      for n in g.nodes() {
        if n.payload is Some(v) {
          out.push(v)
        }
      }
      for e in g.edges() {
        if e.payload is Some(v) {
          out.push(v)
        }
      }
      out
    }
    _ => []
  }
}

///|
priv enum FoldStep[N] {
  Visit(N)
  Build(N, Int32)
}

///|
/// Folds a value tree from leaves to root without using the call stack.
/// `prepare` runs before descending; `f` receives the prepared value and
/// its folded children in stored order: list/bag items, tuple values,
/// alternating map keys and values, then graph node/edge payloads.
/// Boxed Ion values are leaves unless `prepare` lowers them.
pub fn[A] Value::fold(
  self : Value,
  f : (Value, Array[A]) -> A raise?,
  prepare~ : (Value) -> Value = v => v,
) -> A raise? {
  fold_tree(self, Value::children, f, prepare~)
}

///|
fn[N, A] fold_tree(
  root : N,
  children : (N) -> Array[N],
  f : (N, Array[A]) -> A raise?,
  prepare~ : (N) -> N = v => v,
) -> A raise? {
  let work = [FoldStep::Visit(root)]
  let results : Array[A] = []
  while work.pop() is Some(step) {
    match step {
      Visit(v) => {
        let node = prepare(v)
        let children = children(node)
        work.push(Build(node, children.length()))
        for i = children.length() - 1; i >= 0; i = i - 1 {
          work.push(Visit(children[i]))
        }
      }
      Build(node, count) => {
        let start = results.length() - count
        let children = results[start:].to_owned()
        results.truncate(start)
        results.push(f(node, children))
      }
    }
  }
  results[0]
}
