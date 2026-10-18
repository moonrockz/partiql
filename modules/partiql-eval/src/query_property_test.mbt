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
fn run(source : String, mode~ : @eval.Mode = Permissive) -> @value.Value {
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
  "<<{'a': 1, 'b': 2}, {'b': 'x'}>>", "{'a': 1}", "5",
]

///|
fn gen_query(rs : @splitmix.RandomState) -> String {
  let e = () => gen_expr(rs, 2)
  let src = query_sources[pick(rs, query_sources.length())]
  let src2 = query_sources[pick(rs, query_sources.length())]
  match pick(rs, 17) {
    0 => "SELECT VALUE (\{e()}) FROM \{src} AS x"
    1 => "SELECT VALUE x FROM \{src} AS x WHERE \{e()}"
    2 => "SELECT (\{e()}) AS v, x FROM \{src} AS x"
    3 => "SELECT DISTINCT VALUE (\{e()}) FROM \{src} AS x"
    4 => "SELECT VALUE y FROM \{src} AS x LEFT JOIN \{src2} AS y ON \{e()}"
    5 => "SELECT VALUE (\{e()}) FROM \{src} AS x LET (\{e()}) AS z"
    // the M4b1 gaps (partiql-7nl)
    6 =>
      "SELECT VALUE x FROM \{src} AS x WHERE (SELECT y FROM \{src2} AS y) = \{e()}"
    7 =>
      "SELECT VALUE [x, y] FROM \{src} AS x RIGHT JOIN \{src2} AS y ON \{e()}"
    8 => "SELECT VALUE [k, v] FROM UNPIVOT \{src} AS v AT k"
    9 => "SELECT VALUE i FROM \{src} AS x AT i"
    10 => "SELECT VALUE a FROM \{src} AS x"
    11 => "SELECT * FROM \{src} AS x, \{src2} AS y"
    // M4b2: ORDER BY, LIMIT, OUTER UNION and PIVOT
    13 => "SELECT VALUE x FROM \{src} AS x ORDER BY \{e()}"
    14 => "SELECT VALUE x FROM \{src} AS x LIMIT \{e()}"
    15 => "\{src} OUTER UNION \{src2}"
    16 => "PIVOT x AT \{e()} FROM \{src} AS x"
    // DataError branch: a FROM variable declared twice, or @ on an unknown name
    _ =>
      if pick(rs, 2) == 0 {
        "SELECT VALUE x FROM \{src} AS x, \{src2} AS x"
      } else {
        "SELECT VALUE @nope FROM \{src} AS x"
      }
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
  let rs = @splitmix.RandomState(seed=11UL)
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
    soft.expect(data_error * 20 >= total).to_be_true()
  })
}

///|
fn count_of(v : @value.Value) -> Int32 {
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
    @value.Tuple::Tuple([("c", Bag(@value.Bag::Bag(items))), ("l", List(items))]),
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
  @expect.expect(v).to_equal(@value.Value::Bag(@value.Bag::Bag([Int(1L)])))
}

///|
/// The parser accepts about 30 nested subqueries; the evaluator must run the
/// deepest one it accepts without a stack overflow.
fn nested_subquery(depth : Int32) -> String {
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

///|
/// A bag literal of the elements of a `CollText`.
fn bag_text(c : CollText) -> String {
  "<<\{c.items.join(", ")}>>"
}

///|
fn count_eqg(items : Array[@value.Value], v : @value.Value) -> Int32 {
  let mut n = 0
  for x in items {
    if @value.eqg(x, v) {
      n += 1
    }
  }
  n
}

///|
/// Equal as bags under grouping equivalence: the same length and, for every
/// element of either side, the same count on both sides.
fn bag_eqg(a : Array[@value.Value], b : Array[@value.Value]) -> Bool {
  a.length() == b.length() &&
  a.iter().all(v => count_eqg(a, v) == count_eqg(b, v)) &&
  b.iter().all(v => count_eqg(a, v) == count_eqg(b, v))
}

///|
test "law: ORDER BY is a permutation of its input" {
  @quickcheck.check(
    (c : CollText) => {
      let sorted = items_of(
        run("SELECT VALUE x FROM \{c.text()} AS x ORDER BY x"),
      )
      let plain = items_of(run("SELECT VALUE x FROM \{c.text()} AS x"))
      match (sorted, plain) {
        (Some(a), Some(b)) =>
          @value.Value::Bag(@value.Bag::Bag(a)) ==
          @value.Value::Bag(@value.Bag::Bag(b))
        _ => false
      }
    },
    count=1000,
  )
}

///|
test "law: ORDER BY output is sorted, ASC nulls last and DESC nulls first" {
  @quickcheck.check(
    (c : CollText) => {
      let asc = match
        items_of(run("SELECT VALUE x FROM \{c.text()} AS x ORDER BY x")) {
        Some(a) => a
        None => return false
      }
      let desc = match
        items_of(run("SELECT VALUE x FROM \{c.text()} AS x ORDER BY x DESC")) {
        Some(a) => a
        None => return false
      }
      for i in 1..<asc.length() {
        if @value.compare(asc[i - 1], asc[i], nulls=NullsLast) > 0 {
          return false
        }
      }
      for i in 1..<desc.length() {
        // DESC reverses the whole ascending order, so NULL (greatest) comes first
        if @value.compare(desc[i - 1], desc[i], nulls=NullsLast) < 0 {
          return false
        }
      }
      true
    },
    count=1000,
  )
}

///|
/// A list source: the stability law needs positions.
struct ListText {
  text : String
} derive(Debug)

///|
impl @quickcheck.Arbitrary for ListText with fn arbitrary(_size, rs) {
  // repeated atoms (and 1, 1.0 and 2e0 style ties) make equal keys likely
  let n = pick(rs, 9)
  let items = Array::makei(n, _ => coll_atoms[pick(rs, coll_atoms.length())])
  { text: "[\{items.join(", ")}]", }
}

///|
impl @quickcheck.Shrink for ListText

///|
test "law: ORDER BY is stable" {
  @quickcheck.check(
    (l : ListText) => {
      let check_dir = (suffix : String) => {
        let out = match
          items_of(
            run(
              "SELECT VALUE [x, i] FROM \{l.text} AS x AT i ORDER BY x\{suffix}",
            ),
          ) {
          Some(a) => a
          None => return false
        }
        for k in 1..<out.length() {
          match (out[k - 1], out[k]) {
            (List([x1, Int(i1)]), List([x2, Int(i2)])) =>
              if @value.compare(x1, x2, nulls=NullsLast) == 0 &&
                @value.compare(x1, x2, nulls=NullsFirst) == 0 &&
                i1 >= i2 {
                return false
              }
            _ => return false
          }
        }
        true
      }
      check_dir("") && check_dir(" DESC")
    },
    count=1000,
  )
}

///|
struct SliceCase {
  c : CollText
  n : Int32
  m : Int32
} derive(Debug)

///|
impl @quickcheck.Arbitrary for SliceCase with fn arbitrary(size, rs) {
  {
    c: @quickcheck.Arbitrary::arbitrary(size, rs),
    n: pick(rs, 8),
    m: pick(rs, 8),
  }
}

///|
impl @quickcheck.Shrink for SliceCase

///|
test "law: LIMIT and OFFSET take the slice of the ordered output" {
  @quickcheck.check(
    (s : SliceCase) => {
      let base = "SELECT VALUE x FROM \{s.c.text()} AS x ORDER BY x"
      let all = match items_of(run(base)) {
        Some(a) => a
        None => return false
      }
      let got = items_of(run("\{base} LIMIT \{s.n} OFFSET \{s.m}"))
      let lo = if s.m > all.length() { all.length() } else { s.m }
      let hi = if s.m + s.n > all.length() { all.length() } else { s.m + s.n }
      match got {
        Some(a) => a == all[lo:hi].to_owned()
        None => false
      }
    },
    count=1000,
  )
}

///|
test "law: OUTER operators obey the multiplicity rules" {
  @quickcheck.check(
    (p : (CollText, CollText)) => {
      let (a, b) = p
      let ia = match items_of(run(bag_text(a))) {
        Some(x) => x
        None => return false
      }
      let ib = match items_of(run(bag_text(b))) {
        Some(x) => x
        None => return false
      }
      let q = (op : String) => {
        items_of(run("\{bag_text(a)} OUTER \{op} ALL \{bag_text(b)}"))
      }
      let union_all = match q("UNION") {
        Some(x) => x
        None => return false
      }
      let inter_all = match q("INTERSECT") {
        Some(x) => x
        None => return false
      }
      let except_all = match q("EXCEPT") {
        Some(x) => x
        None => return false
      }
      let universe = ia + ib
      universe
      .iter()
      .all(v => {
        let ca = count_eqg(ia, v)
        let cb = count_eqg(ib, v)
        count_eqg(union_all, v) == ca + cb &&
        count_eqg(inter_all, v) == (if ca < cb { ca } else { cb }) &&
        count_eqg(except_all, v) == (if ca > cb { ca - cb } else { 0 })
      }) &&
      union_all.length() == ia.length() + ib.length() &&
      inter_all.iter().all(v => count_eqg(universe, v) > 0) &&
      except_all.iter().all(v => count_eqg(ia, v) > 0)
    },
    count=1000,
  )
}

///|
/// UNION and INTERSECT DISTINCT are DISTINCT over the ALL form. EXCEPT is not:
/// EXCEPT ALL keeps `count_a - count_b` copies, but EXCEPT DISTINCT keeps a
/// distinct left value only when the right side has none of it.
test "law: OUTER DISTINCT forms are DISTINCT over the ALL forms" {
  @quickcheck.check(
    (p : (CollText, CollText)) => {
      let (a, b) = p
      let ib = match items_of(run(bag_text(b))) {
        Some(x) => x
        None => return false
      }
      let distinct_a = match
        items_of(run("SELECT DISTINCT VALUE x FROM \{bag_text(a)} AS x")) {
        Some(x) => x
        None => return false
      }
      let except_ok = match
        items_of(run("\{bag_text(a)} OUTER EXCEPT \{bag_text(b)}")) {
        Some(d) => bag_eqg(d, distinct_a.filter(v => count_eqg(ib, v) == 0))
        None => false
      }
      except_ok &&
      ["UNION", "INTERSECT"]
      .iter()
      .all(op => {
        let distinct = items_of(
          run("\{bag_text(a)} OUTER \{op} \{bag_text(b)}"),
        )
        let over = items_of(
          run(
            "WITH u AS (\{bag_text(a)} OUTER \{op} ALL \{bag_text(b)}) SELECT DISTINCT VALUE x FROM u AS x",
          ),
        )
        match (distinct, over) {
          (Some(d), Some(o)) => bag_eqg(d, o)
          _ => false
        }
      })
    },
    count=1000,
  )
}

///|
/// Relations: bags of one-attribute tuples over one type class, so the SQL
/// operators raise no DataError.
struct RelText {
  items : Array[String]
} derive(Debug)

///|
let rel_atoms : Array[String] = ["0", "1", "-1", "7", "2e0", "1.5", "NULL"]

///|
impl @quickcheck.Arbitrary for RelText with fn arbitrary(_size, rs) {
  let n = pick(rs, 7)
  {
    items: Array::makei(n, _ => {
      "{'a': \{rel_atoms[pick(rs, rel_atoms.length())]}}"
    }),
  }
}

///|
impl @quickcheck.Shrink for RelText

///|
fn RelText::text(self : RelText) -> String {
  "<<\{self.items.join(", ")}>>"
}

///|
test "law: OUTER operators equal the SQL operators on relations" {
  @quickcheck.check(
    (p : (RelText, RelText)) => {
      let (a, b) = p
      for op in ["UNION", "INTERSECT", "EXCEPT"] {
        for quant in ["", " ALL", " DISTINCT"] {
          let outer = items_of(
            run("\{a.text()} OUTER \{op}\{quant} \{b.text()}"),
          )
          let sql = items_of(run("\{a.text()} \{op}\{quant} \{b.text()}"))
          // the atoms share one type class, so neither form may raise
          match (outer, sql) {
            (Some(o), Some(s)) => if !bag_eqg(o, s) { return false }
            _ => return false
          }
        }
      }
      true
    },
    count=1000,
  )
}

///|
test "totality: ORDER BY over a 100000-element bag" {
  let n = 100000
  let items : Array[@value.Value] = Array::makei(n, i => {
    Int((i * 7919 % n).to_int64())
  })
  let env = @eval.Bindings::of_tuple(
    @value.Tuple::Tuple([("c", Bag(@value.Bag::Bag(items)))]),
  )
  let v = @eval.evaluate_text("SELECT VALUE x FROM c AS x ORDER BY x", env~)
  let out = items_of(v).unwrap()
  @expect.expect_all(soft => {
    soft.expect(out.length()).to_equal(n)
    soft.expect(out[0]).to_equal(Int(0L))
    soft.expect(out[n - 1]).to_equal(Int((n - 1).to_int64()))
  })
}

///|
test "totality: OUTER and SQL set operations over two 100000-element bags" {
  let n = 100000
  let ints = (lo : Int32) => {
    Array::makei(n, i => @value.Value::Int((lo + i).to_int64()))
  }
  let tuples = (lo : Int32) => {
    Array::makei(n, i => {
      @value.Value::from_tuple(@value.Tuple([("a", Int((lo + i).to_int64()))]))
    })
  }
  let env = @eval.Bindings::of_tuple(
    @value.Tuple::Tuple([
      ("c", Bag(@value.Bag::Bag(ints(0)))),
      ("d", Bag(@value.Bag::Bag(ints(n / 2)))),
      ("t", Bag(@value.Bag::Bag(tuples(0)))),
      ("u", Bag(@value.Bag::Bag(tuples(n / 2)))),
    ]),
  )
  let q = (s : String) => @eval.evaluate_text(s, env~)
  let outer_union_all = q("c OUTER UNION ALL d")
  let outer_intersect = q("c OUTER INTERSECT d")
  let sql_union = q("t UNION u")
  @expect.expect_all(soft => {
    soft.expect(count_of(outer_union_all)).to_equal(2 * n)
    soft.expect(count_of(outer_intersect)).to_equal(n / 2)
    soft.expect(count_of(sql_union)).to_equal(n + n / 2)
  })
}

///|
test "totality: a chain of 300 OUTER UNIONs" {
  let chain = Array::makei(300, i => "<<\{i}>>").join(" OUTER UNION ")
  let v = ev(chain)
  @expect.expect(count_of(v)).to_equal(300)
}

///|
test "totality: WITH with 50 chained bindings" {
  let bindings = Array::makei(50, i => {
    if i == 0 {
      "w0 AS (SELECT VALUE 1 FROM [0] AS z)"
    } else {
      "w\{i} AS (SELECT VALUE x + 1 FROM w\{i - 1} AS x)"
    }
  }).join(", ")
  let v = ev("WITH \{bindings} SELECT VALUE y FROM w49 AS y")
  @expect.expect(v).to_equal(@value.Value::Bag(@value.Bag::Bag([Int(50L)])))
}
