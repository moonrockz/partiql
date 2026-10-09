///|
/// A collection literal of atoms: a list or a bag, as text and as items.
struct CollText {
  open : String
  close : String
  items : Array[String]
} derive(Debug)

///|
let coll_atoms : Array[String] = [
  "0", "1", "-1", "7", "1.5", "2e0", "'a'", "'b'", "''", "TRUE", "FALSE", "NULL",
  "[1, 2]", "{'a': 1}", "<<1>>",
]

///|
impl @quickcheck.Arbitrary for CollText with fn arbitrary(_size, rs) {
  let n = pick(rs, 7)
  let items = Array::makei(n, _ => coll_atoms[pick(rs, coll_atoms.length())])
  if pick(rs, 2) == 0 {
    { open: "[", close: "]", items, }
  } else {
    { open: "<<", close: ">>", items, }
  }
}

///|
impl @quickcheck.Shrink for CollText

///|
fn CollText::text(self : CollText) -> String {
  "\{self.open}\{self.items.join(", ")}\{self.close}"
}

///|
/// The elements as a bag, built from a bag literal.
fn CollText::as_bag(self : CollText) -> @value.Value raise @eval.EvalError {
  ev("<<\{self.items.join(", ")}>>")
}

///|
/// Run a query, in permissive mode, as a value; a failure is a String that no
/// expected value equals.
fn run(source : String, mode? : @eval.Mode = Permissive) -> @value.Value {
  ev(source, mode~) catch {
    e => String("error: \{@debug.to_string(e)}")
  }
}

///|
test "law: SELECT VALUE x FROM c AS x is the elements of c as a bag" {
  @quickcheck.check(
    (c : CollText) => {
      let expected = c.as_bag() catch { _ => return false }
      run("SELECT VALUE x FROM \{c.text()} AS x") == expected &&
      run("SELECT VALUE x FROM \{c.text()} AS x", mode=Strict) == expected
    },
    count=1000,
  )
}

///|
test "law: WHERE TRUE changes nothing" {
  @quickcheck.check(
    (c : CollText) => {
      let q = "SELECT VALUE x FROM \{c.text()} AS x"
      run(q + " WHERE TRUE") == run(q) &&
      run("SELECT x FROM \{c.text()} AS x WHERE TRUE") ==
      run("SELECT x FROM \{c.text()} AS x")
    },
    count=1000,
  )
}

///|
test "law: ON TRUE join is the comma cross product" {
  @quickcheck.check(
    (p : (CollText, CollText)) => {
      let (a, b) = p
      let comma = run("SELECT x, y FROM \{a.text()} AS x, \{b.text()} AS y")
      let inner = run(
        "SELECT x, y FROM \{a.text()} AS x INNER JOIN \{b.text()} AS y ON TRUE",
      )
      let cross = run(
        "SELECT x, y FROM \{a.text()} AS x CROSS JOIN \{b.text()} AS y",
      )
      let left = run(
        "SELECT x, y FROM \{a.text()} AS x LEFT JOIN \{b.text()} AS y ON TRUE",
      )
      let right = run(
        "SELECT x, y FROM \{a.text()} AS x RIGHT JOIN \{b.text()} AS y ON TRUE",
      )
      let count = (v : @value.Value) => {
        match v {
          Bag(bag) => bag.length()
          _ => -1
        }
      }
      comma == inner &&
      comma == cross &&
      count(comma) == a.items.length() * b.items.length() &&
      // an empty side leaves unmatched rows in an outer join
      (
        a.items.is_empty() ||
        b.items.is_empty() ||
        (left == comma && right == comma)
      )
    },
    count=500,
  )
}

///|
test "law: a LEFT JOIN keeps every left row" {
  @quickcheck.check(
    (p : (CollText, CollText)) => {
      let (a, b) = p
      // ON FALSE matches nothing: one row per left element, y absent
      let v = run(
        "SELECT VALUE x FROM \{a.text()} AS x LEFT JOIN \{b.text()} AS y ON FALSE",
      )
      v == (a.as_bag() catch { _ => return false })
    },
    count=500,
  )
}

///|
/// Atoms for DISTINCT: numbers equal across kinds (1, 1.0, 1e0), NULL and
/// MISSING, so the grouping-equivalence path is exercised.
let distinct_atoms : Array[String] = [
  "1", "1.0", "1e0", "`1.0e0`", "2", "2.0", "2e0", "'a'", "'a'", "NULL", "MISSING",
  "TRUE", "[1]", "[1.0]", "{'a': 1}", "{'a': 1.0}", "<<1>>", "<<1.0>>",
]

///|
struct DistinctText {
  text : String
} derive(Debug)

///|
impl @quickcheck.Arbitrary for DistinctText with fn arbitrary(_size, rs) {
  let n = pick(rs, 9)
  let items = Array::makei(n, _ => {
    distinct_atoms[pick(rs, distinct_atoms.length())]
  })
  { text: "[\{items.join(", ")}]", }
}

///|
impl @quickcheck.Shrink for DistinctText

///|
fn items_of(v : @value.Value) -> Array[@value.Value]? {
  match v {
    Bag(b) => Some(b.items().to_owned())
    List(l) => Some(l)
    _ => None
  }
}

///|
test "law: SELECT DISTINCT is idempotent" {
  @quickcheck.check(
    (c : DistinctText) => {
      let once = run("SELECT DISTINCT VALUE x FROM \{c.text} AS x")
      let twice = run(
        "SELECT DISTINCT VALUE x FROM (SELECT DISTINCT VALUE x FROM \{c.text} AS x) AS x",
      )
      once == twice && once is Bag(_)
    },
    count=1000,
  )
}

///|
/// DISTINCT keeps one element per grouping-equivalence class: no two result
/// elements are eqg, every input element has an eqg result element, and every
/// result element is an input element.
test "law: SELECT DISTINCT VALUE keeps one element per class and drops none" {
  @quickcheck.check(
    (c : DistinctText) => {
      let input = match items_of(run("SELECT VALUE x FROM \{c.text} AS x")) {
        Some(items) => items
        None => return false
      }
      let out = match
        items_of(run("SELECT DISTINCT VALUE x FROM \{c.text} AS x")) {
        Some(items) => items
        None => return false
      }
      for i in 0..<out.length() {
        for j in (i + 1)..<out.length() {
          if @value.eqg(out[i], out[j]) {
            return false
          }
        }
      }
      input.iter().all(x => out.iter().any(y => @value.eqg(x, y))) &&
      out.iter().all(y => input.iter().any(x => @value.eqg(x, y)))
    },
    count=1000,
  )
}

///|
test "SELECT DISTINCT VALUE merges grouping-equal numbers of every kind" {
  @expect.expect_all(soft => {
    soft
    .expect(count_of(run("SELECT DISTINCT VALUE x FROM <<1, 1.0, 1e0>> AS x")))
    .to_equal(1)
    soft
    .expect(
      count_of(run("SELECT DISTINCT VALUE x FROM <<1, 2, 1.0, 2e0>> AS x")),
    )
    .to_equal(2)
    soft
    .expect(
      count_of(run("SELECT DISTINCT VALUE x FROM <<NULL, NULL, 1>> AS x")),
    )
    .to_equal(2)
    soft
    .expect(
      count_of(run("SELECT DISTINCT VALUE x FROM [MISSING, MISSING, 1] AS x")),
    )
    .to_equal(2)
  })
}

///|
/// A generated query: expression texts of the M4a generator under the query
/// forms, so strict and permissive modes can differ.
struct QueryText {
  text : String
} derive(Debug)

///|
let query_sources : Array[String] = [
  "[1, 2, 3]", "<<1, 'a', NULL>>", "[{'a': 1}, {'a': 'b'}]", "[]", "[1.5, 2e0, 7]",
]

///|
fn gen_query(rs : @splitmix.RandomState) -> String {
  let e = () => gen_expr(rs, 2)
  let src = query_sources[pick(rs, query_sources.length())]
  match pick(rs, 6) {
    0 => "SELECT VALUE (\{e()}) FROM \{src} AS x"
    1 => "SELECT VALUE x FROM \{src} AS x WHERE \{e()}"
    2 => "SELECT (\{e()}) AS v, x FROM \{src} AS x"
    3 => "SELECT DISTINCT VALUE (\{e()}) FROM \{src} AS x"
    4 => "SELECT VALUE y FROM \{src} AS x LEFT JOIN \{src} AS y ON \{e()}"
    _ => "SELECT VALUE (\{e()}) FROM \{src} AS x LET (\{e()}) AS z"
  }
}

///|
impl @quickcheck.Arbitrary for QueryText with fn arbitrary(_size, rs) {
  { text: gen_query(rs), }
}

///|
impl @quickcheck.Shrink for QueryText

///|
test "law: modes agree on generated queries" {
  // The one-operator refinement does not hold: a failed operation can drop a
  // row from a WHERE or ON, so permissive may give any value.
  @quickcheck.check((q : QueryText) => modes_agree(q.text, false), count=2000)
}

///|
test "law: the query generator reaches every branch of the modes law" {
  let rs = @splitmix.new(seed=11UL)
  let mut ok = 0
  let mut type_error = 0
  let mut data_error = 0
  let mut other = 0
  let total = 2000
  for _ in 0..<total {
    match outcome(gen_query(rs), Strict) {
      Val(_) => ok += 1
      Type => type_error += 1
      Data => data_error += 1
      Other => other += 1
    }
  }
  println(
    "query modes law branches of \{total}: ok=\{ok} type=\{type_error} data=\{data_error} other=\{other}",
  )
  @expect.expect_all(soft => {
    soft.expect(other).to_equal(0)
    soft.expect(ok * 10 >= total).to_be_true()
    soft.expect(type_error * 20 >= total).to_be_true()
  })
}

///|
fn count_of(v : @value.Value) -> Int {
  match v {
    Bag(b) => b.length()
    _ => -1
  }
}

///|
test "totality: a 100000-element bag through scan, filter and project" {
  let n = 100000
  let items : Array[@value.Value] = Array::makei(n, i => Int(i.to_int64()))
  let env = @eval.Bindings::of_tuple(
    @value.Tuple::new([("c", Bag(@value.Bag::new(items))), ("l", List(items))]),
  )
  let q = (s : String) => @eval.evaluate_text(s, env~)
  let scan = q("SELECT VALUE x FROM c AS x")
  let filtered = q("SELECT VALUE x FROM c AS x WHERE x % 2 = 0")
  let projected = q("SELECT x + 1 AS y FROM c AS x WHERE x < 50000")
  let distinct = q("SELECT DISTINCT VALUE x % 10 FROM c AS x")
  let from_list = q("SELECT VALUE x FROM l AS x WHERE x >= 0")
  @expect.expect_all(soft => {
    soft.expect(count_of(scan)).to_equal(n)
    soft.expect(count_of(filtered)).to_equal(n / 2)
    soft.expect(count_of(projected)).to_equal(50000)
    soft.expect(count_of(distinct)).to_equal(10)
    soft.expect(count_of(from_list)).to_equal(n)
  })
}

///|
test "totality: a 300-item comma FROM list" {
  let from = Array::makei(300, i => "[\{i}] AS x\{i}").join(", ")
  // 300 singleton sources: one row
  let v = ev("SELECT VALUE 1 FROM \{from}")
  @expect.expect(v).to_equal(@value.Value::Bag(@value.Bag::new([Int(1L)])))
}

///|
/// The parser accepts about 30 nested subqueries; the evaluator must run the
/// deepest one it accepts without a stack overflow.
fn nested_subquery(depth : Int) -> String {
  let mut s = "1"
  for _ in 0..<depth {
    s = "(SELECT VALUE x FROM [\{s}] AS x)"
  }
  s
}

///|
test "totality: subqueries nested as deep as the parser accepts" {
  let mut deepest = 0
  for d in 1..<60 {
    let src = "SELECT VALUE x FROM [\{nested_subquery(d)}] AS x"
    try ev(src) catch {
      _ => break
    } noraise {
      _ => deepest = d
    }
  }
  println("deepest nested subquery depth evaluated: \{deepest}")
  @expect.expect(deepest >= 25).to_be_true()
}
