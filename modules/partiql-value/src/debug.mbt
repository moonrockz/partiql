///|
fn graph_repr(g : GraphValue, children : Array[Repr]) -> Repr {
  let mut at = 0
  let payload = (p : Value?) => {
    match p {
      None => Repr::ctor("None", [])
      Some(_) => {
        let r = children[at]
        at += 1
        Repr::ctor("Some", [(None, r)])
      }
    }
  }
  let nodes = g
    .nodes()
    .map(n => {
      Repr::record({
        "id": Repr(n.id),
        "labels": Repr(n.labels),
        "payload": payload(n.payload),
      })
    })
  let edges = g
    .edges()
    .map(e => {
      Repr::record({
        "id": Repr(e.id),
        "labels": Repr(e.labels),
        "ends": Repr(e.ends),
        "payload": payload(e.payload),
      })
    })
  Repr::record({ "nodes": Repr::array(nodes), "edges": Repr::array(edges) })
}

///|
fn ion_repr(x : @ion_core.IonValue) -> Repr {
  fold_tree(
    x,
    v => {
      match v.kind() {
        List(xs) | Sexp(xs) => xs
        Struct(fs) => fs.map(f => f.value())
        _ => []
      }
    },
    (v, children) => {
      let kind = match v.kind() {
        List(_) => Repr::ctor("List", [(None, Repr::array(children))])
        Sexp(_) => Repr::ctor("Sexp", [(None, Repr::array(children))])
        Struct(fs) =>
          Repr::ctor("Struct", [
            (
              None,
              Repr::array(
                fs.mapi((i, f) => {
                  Repr::record({ "name": Repr(f.name()), "value": children[i] })
                }),
              ),
            ),
          ])
        scalar => Repr(scalar)
      }
      Repr::record({ "annotations": Repr(v.annotations()), "kind": kind })
    },
  )
}

///|
pub impl @debug.Debug for Value with fn to_repr(self) {
  self.fold((v, children) => {
    let ctor = (name : String, arg : Repr) => Repr::ctor(name, [(None, arg)])
    match v {
      Null => Repr::ctor("Null", [])
      Missing => Repr::ctor("Missing", [])
      Bool(x) => ctor("Bool", Repr(x))
      Int(x) => ctor("Int", Repr(x))
      BigInt(x) => ctor("BigInt", Repr(x))
      Float(x) => ctor("Float", Repr(x))
      Decimal(x) => ctor("Decimal", Repr(x))
      String(x) => ctor("String", Repr(x))
      Clob(x) => ctor("Clob", Repr(x))
      Blob(x) => ctor("Blob", Repr(x))
      Date(x) => ctor("Date", Repr(x))
      Time(x) => ctor("Time", Repr(x))
      Timestamp(x) => ctor("Timestamp", Repr(x))
      IntervalYM(x) => ctor("IntervalYM", Repr(x))
      IntervalDT(x) => ctor("IntervalDT", Repr(x))
      List(_) => ctor("List", Repr::array(children))
      Bag(_) => ctor("Bag", Repr::record({ "items": Repr::array(children) }))
      Tuple(t) =>
        ctor(
          "Tuple",
          Repr::record({
            "fields": Repr::array(
              t.fields().mapi((i, p) => Repr::tuple([Repr(p.0), children[i]])),
            ),
          }),
        )
      Map(m) =>
        ctor(
          "Map",
          Repr::record({
            "key_type": Repr(m.key_type),
            "value_type": Repr(m.value_type),
            "entries": Repr::array(
              m
              .entries()
              .mapi((i, _) => {
                Repr::tuple([children[2 * i], children[2 * i + 1]])
              }),
            ),
          }),
        )
      Graph(g) => ctor("Graph", graph_repr(g, children))
      Ion(x) => ctor("Ion", ion_repr(x))
    }
  })
}

///|
pub impl @debug.Debug for Bag with fn to_repr(self) {
  Repr::record({ "items": Repr(self.items) })
}

///|
pub impl @debug.Debug for Tuple with fn to_repr(self) {
  Repr::record({ "fields": Repr(self.fields) })
}

///|
pub impl @debug.Debug for MapValue with fn to_repr(self) {
  Repr::record({
    "key_type": Repr(self.key_type),
    "value_type": Repr(self.value_type),
    "entries": Repr(self.entries),
  })
}

///|
pub impl @debug.Debug for GraphNode with fn to_repr(self) {
  Repr::record({
    "id": Repr(self.id),
    "labels": Repr(self.labels),
    "payload": Repr(self.payload),
  })
}

///|
pub impl @debug.Debug for GraphEdge with fn to_repr(self) {
  Repr::record({
    "id": Repr(self.id),
    "labels": Repr(self.labels),
    "ends": Repr(self.ends),
    "payload": Repr(self.payload),
  })
}

///|
pub impl @debug.Debug for GraphValue with fn to_repr(self) {
  graph_repr(self, Value::Graph(self).children().map(v => Repr(v)))
}
