///|
/// Rows `{'k': key, 'v': value}` with few keys and mixed values.
struct Rows {
  rows : Array[(String, String)]
} derive(Debug)

///|
let row_keys : Array[String] = ["1", "2", "1.0", "NULL", "MISSING", "'a'"]

///|
let row_values : Array[String] = [
  "0", "1", "-3", "7", "1.5", "2e0", "NULL", "MISSING", "'s'", "TRUE", "FALSE",
]

///|
impl @quickcheck.Arbitrary for Rows with fn arbitrary(_size, rs) {
  let n = pick(rs, 8)
  {
    rows: Array::makei(n, _ => {
      (
        row_keys[pick(rs, row_keys.length())],
        row_values[pick(rs, row_values.length())],
      )
    }),
  }
}

///|
impl @quickcheck.Shrink for Rows

///|
fn Rows::text(self : Rows) -> String {
  "<<" + self.rows.map(r => "{'k': \{r.0}, 'v': \{r.1}}").join(", ") + ">>"
}

///|
/// A query's value, or the kind of its error: the two sides of a law fail
/// at different spans, so only the kind of error is compared.
fn result_kind(
  source : String,
  mode~ : @eval.Mode = Permissive,
) -> @value.Value {
  ev(source, mode~) catch {
    TypeError(..) => @value.Value::from_string("error: TypeError")
    DataError(..) => @value.Value::from_string("error: DataError")
    Unsupported(..) => @value.Value::from_string("error: Unsupported")
    Syntax(_) => @value.Value::from_string("error: Syntax")
  }
}

///|
let kinds : Array[String] = [
  "COUNT", "SUM", "AVG", "MIN", "MAX", "ANY", "EVERY",
]

///|
test "law: a SQL aggregate equals its spec rewrite onto COLL_ over the group" {
  @quickcheck.check(
    (rows : Rows) => {
      let data = rows.text()
      kinds
      .iter()
      .all(f => {
        let quantifiers = ["", "DISTINCT "]
        quantifiers
        .iter()
        .all(q => {
          let sql = "SELECT k, \{f}(\{q}t.v) AS s FROM \{data} AS t GROUP BY t.k AS k"
          let core = "SELECT k, COLL_\{f}(\{q}(SELECT VALUE p.t.v FROM g AS p)) AS s FROM \{data} AS t GROUP BY t.k AS k GROUP AS g"
          let all_sql = "SELECT VALUE \{f}(\{q}t.v) FROM \{data} AS t"
          let all_core = "SELECT VALUE COLL_\{f}(\{q}(SELECT VALUE p.t.v FROM g AS p)) FROM \{data} AS t GROUP ALL AS g"
          result_kind(sql) == result_kind(core) &&
          result_kind(sql, mode=Strict) == result_kind(core, mode=Strict) &&
          result_kind(all_sql) == result_kind(all_core) &&
          result_kind(all_sql, mode=Strict) ==
          result_kind(all_core, mode=Strict)
        })
      })
    },
    count=300,
  )
}

///|
test "law: an aggregate does not depend on the order of its values" {
  @quickcheck.check(
    (c : CollText) => {
      let reversed = { ..c, items: c.items.rev(), }
      kinds
      .iter()
      .all(f => {
        run("COLL_\{f}(\{c.text()})") == run("COLL_\{f}(\{reversed.text()})")
      })
    },
    count=500,
  )
}

///|
test "law: DISTINCT is the aggregate of the values without repeats" {
  @quickcheck.check(
    (c : CollText) => {
      kinds
      .iter()
      .all(f => {
        run("COLL_\{f}(DISTINCT \{c.text()})") ==
        run("COLL_\{f}(SELECT DISTINCT VALUE x FROM \{c.text()} AS x)")
      })
    },
    count=500,
  )
}

///|
test "law: COUNT is the number of values that are not NULL or MISSING" {
  @quickcheck.check(
    (c : CollText) => {
      run("COLL_COUNT(\{c.text()})") ==
      run(
        "COLL_COUNT(SELECT VALUE x FROM \{c.text()} AS x WHERE x IS NOT NULL)",
      )
    },
    count=500,
  )
}

///|
test "law: MIN and MAX bound every value in the total order" {
  @quickcheck.check(
    (c : CollText) => {
      let lo = run("COLL_MIN(\{c.text()})")
      let hi = run("COLL_MAX(\{c.text()})")
      let present = c.items.filter(x => x != "NULL").map(x => run(x))
      present
      .iter()
      .all(x => {
        @value.compare(lo, x, nulls=NullsFirst) <= 0 &&
        @value.compare(x, hi, nulls=NullsFirst) <= 0
      })
    },
    count=500,
  )
}
