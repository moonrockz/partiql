///|
/// Where NULL and MISSING sort.
pub(all) enum NullOrder {
  NullsFirst
  NullsLast
} derive(Debug, Eq)

///|
fn rank(v : Value) -> Int32 {
  match v {
    Null | Missing => 0
    Bool(_) => 1
    Int(_) | BigInt(_) | Float(_) | Decimal(_) => 2
    Date(_) => 3
    Time(_) => 4
    Timestamp(_) => 5
    IntervalYM(_) => 6
    IntervalDT(_) => 7
    String(_) => 8
    Clob(_) | Blob(_) => 9
    List(_) => 10
    Tuple(_) => 11
    Bag(_) => 12
    Map(_) => 13
    Graph(_) => 14
    // Only an Ion value that cannot be lowered (a symbol without text)
    // keeps this rank; such values compare equal to each other.
    Ion(_) => 15
  }
}

///|
fn sign(n : Int32) -> Int32 {
  if n < 0 {
    -1
  } else if n > 0 {
    1
  } else {
    0
  }
}

///|
fn compare_keys(a : (Int64, Int32), b : (Int64, Int32)) -> Int32 {
  let c = a.0.compare(b.0)
  if c != 0 {
    sign(c)
  } else {
    sign(a.1.compare(b.1))
  }
}

///|
/// Key and zone flag. The key is the UTC instant for a zoned value and the
/// fields for an unzoned one; at equal keys, an unzoned value sorts first.
/// (A tie-break on raw fields would not be transitive.)
fn compare_zoned(
  a_key : (Int64, Int32),
  a_zoned : Bool,
  b_key : (Int64, Int32),
  b_zoned : Bool,
) -> Int32 {
  let c = compare_keys(a_key, b_key)
  if c != 0 {
    c
  } else {
    sign(a_zoned.compare(b_zoned))
  }
}

///|
fn lowered_or_self(v : Value) -> Value {
  try v.lower() catch {
    _ => v
  } noraise {
    x => x
  }
}

///|
/// The non-container part of ORDER BY.
fn compare_scalar(a : Value, b : Value, nulls : NullOrder) -> Int32 {
  let x = lowered_or_self(a)
  let y = lowered_or_self(b)
  let (rx, ry) = (rank(x), rank(y))
  if rx == 0 || ry == 0 {
    return match (rx == 0, ry == 0, nulls) {
      (true, true, _) => 0
      (true, false, NullsFirst) | (false, true, NullsLast) => -1
      _ => 1
    }
  }
  if rx != ry {
    return sign(rx.compare(ry))
  }
  match (x, y) {
    (Bool(p), Bool(q)) => sign(p.compare(q))
    (Date(p), Date(q)) =>
      compare_keys(
        (days_from_civil(p.year, p.month, p.day), 0),
        (days_from_civil(q.year, q.month, q.day), 0),
      )
    (Time(p), Time(q)) =>
      compare_zoned(
        if p.offset is Some(_) {
          p.utc_key()
        } else {
          p.local_key()
        },
        p.offset is Some(_),
        if q.offset is Some(_) {
          q.utc_key()
        } else {
          q.local_key()
        },
        q.offset is Some(_),
      )
    (Timestamp(p), Timestamp(q)) =>
      compare_zoned(
        if p.time.offset is Some(_) {
          p.utc_key()
        } else {
          p.local_key()
        },
        p.time.offset is Some(_),
        if q.time.offset is Some(_) {
          q.utc_key()
        } else {
          q.local_key()
        },
        q.time.offset is Some(_),
      )
    (IntervalYM(p), IntervalYM(q)) => sign(p.months.compare(q.months))
    (IntervalDT(p), IntervalDT(q)) =>
      compare_keys((p.seconds, p.nanos), (q.seconds, q.nanos))
    (String(p), String(q)) => compare_text(p, q)
    (Clob(p) | Blob(p), Clob(q) | Blob(q)) => compare_octets(p, q)
    _ =>
      match (num_of(x), num_of(y)) {
        (Some(m), Some(n)) => sign(compare_num(m, n))
        _ => 0
      }
  }
}

///|
priv enum OrderKind {
  List
  Tuple
  Bag
  Map
  Graph
  Component
}

///|
fn OrderKind::rank(self : OrderKind) -> Int32 {
  match self {
    List => 10
    Tuple => 11
    Bag => 12
    Map => 13
    Graph => 14
    Component => 16
  }
}

///|
priv enum OrderValue {
  Scalar(Value)
  Sequence(OrderKind, Array[OrderValue])
}

///|
fn OrderValue::rank(self : OrderValue) -> Int32 {
  match self {
    Scalar(v) => rank(v)
    Sequence(kind, _) => kind.rank()
  }
}

///|
priv enum OrderStep {
  Pair(OrderValue, OrderValue)
  Length(Int32, Int32)
}

///|
/// Canonical children are already sorted. Comparison itself never sorts
/// or calls back into `compare`, including comparisons made by a sort.
fn order_compare(a : OrderValue, b : OrderValue, nulls : NullOrder) -> Int32 {
  let work = [OrderStep::Pair(a, b)]
  while work.pop() is Some(step) {
    let result = match step {
      Length(x, y) => sign(x.compare(y))
      Pair(x, y) => {
        let (rx, ry) = (x.rank(), y.rank())
        if rx != ry {
          if (rx == 0 || ry == 0) && nulls is NullsLast {
            if rx == 0 {
              1
            } else {
              -1
            }
          } else {
            sign(rx.compare(ry))
          }
        } else {
          match (x, y) {
            (Scalar(p), Scalar(q)) => compare_scalar(p, q, nulls)
            (Sequence(_, xs), Sequence(_, ys)) => {
              work.push(Length(xs.length(), ys.length()))
              for i = xs.length().min(ys.length()) - 1; i >= 0; i = i - 1 {
                work.push(Pair(xs[i], ys[i]))
              }
              0
            }
            _ => 0
          }
        }
      }
    }
    if result != 0 {
      return result
    }
  }
  0
}

///|
fn order_form(v : Value, nulls : NullOrder) -> OrderValue {
  v.fold(
    (node, children) => {
      let sequence = (xs : Array[OrderValue]) => {
        OrderValue::Sequence(Component, xs)
      }
      let string = (s : String) => OrderValue::Scalar(Value::from_string(s))
      let sort = (xs : Array[OrderValue]) => {
        xs.sort_by((p, q) => order_compare(p, q, nulls))
        xs
      }
      match node {
        List(_) => Sequence(List, children)
        Bag(_) => Sequence(Bag, sort(children))
        Tuple(t) => {
          let fields = t
            .fields()
            .mapi((i, p) => sequence([string(p.0), children[i]]))
          Sequence(Tuple, sort(fields))
        }
        Map(m) => {
          let entries = m
            .entries()
            .mapi((i, _) => sequence([children[2 * i], children[2 * i + 1]]))
          Sequence(Map, sort(entries))
        }
        Graph(g) => {
          let mut at = 0
          let payload = (p : Value?) => {
            match p {
              None => sequence([])
              Some(_) => {
                let child = children[at]
                at += 1
                sequence([child])
              }
            }
          }
          let labels = (xs : Array[String]) => sequence(sort(xs.map(string)))
          let nodes = g
            .nodes()
            .map(n => {
              sequence([string(n.id), labels(n.labels), payload(n.payload)])
            })
          let edges = g
            .edges()
            .map(e => {
              let ends = match e.ends {
                Directed(from~, to~) =>
                  sequence([
                    Scalar(Value::from_int(0)),
                    string(from),
                    string(to),
                  ])
                Undirected(a, b) => {
                  let (first, last) = if compare_text(a, b) <= 0 {
                    (a, b)
                  } else {
                    (b, a)
                  }
                  sequence([
                    Scalar(Value::from_int(1)),
                    string(first),
                    string(last),
                  ])
                }
              }
              sequence([
                string(e.id),
                labels(e.labels),
                ends,
                payload(e.payload),
              ])
            })
          Sequence(Graph, [sequence(sort(nodes)), sequence(sort(edges))])
        }
        _ => Scalar(node)
      }
    },
    prepare=lowered_or_self,
  )
}

///|
/// The ORDER BY total order (spec section 4.4). Returns -1, 0 or 1.
/// Values are canonicalized bottom-up, then compared with an explicit stack.
pub fn compare(a : Value, b : Value, nulls~ : NullOrder) -> Int32 {
  let x = lowered_or_self(a)
  let y = lowered_or_self(b)
  if rank(x) != rank(y) || rank(x) < 10 || rank(x) == 15 {
    compare_scalar(x, y, nulls)
  } else {
    order_compare(order_form(x, nulls), order_form(y, nulls), nulls)
  }
}
