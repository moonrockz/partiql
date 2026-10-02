// Laws of the pretty layout (spec M3b section 6), at random widths.

///|
/// A random statement and a random width from 1 to 120.
struct WideTree {
  statement : @ast.Statement
  width : Int
} derive(Debug)

///|
impl @quickcheck.Arbitrary for WideTree with fn arbitrary(size, rs) {
  let statement = if chance(rs, 2) {
    let t : TreeSpec = @quickcheck.Arbitrary::arbitrary(size, rs)
    t.statement
  } else {
    let e : ExprSpec = @quickcheck.Arbitrary::arbitrary(size, rs)
    Query(
      simple_query(
        Select({
          quantifier: None,
          projection: Value(e.expr),
          from: None,
          let_: [],
          where_: None,
          group_by: None,
          having: None,
          span: span0,
        }),
      ),
    )
  }
  { statement, width: 1 + pick(rs, 120), }
}

///|
impl @quickcheck.Shrink for WideTree

///|
fn code_points(s : String) -> Int {
  let mut n = 0
  for _ in s {
    n += 1
  }
  n
}

///|
test "law: the pretty text round-trips at every width" {
  @quickcheck.check(
    (t : WideTree) => {
      let printed = @printer.print(t.statement, width=t.width)
      try @parser.parse_statement(printed) catch {
        _ => false
      } noraise {
        back =>
          back.strip_spans() == t.statement.strip_spans() &&
          @printer.print(back, width=t.width) == printed
      }
    },
    count=1000,
  )
}

///|
test "law: a statement that fits stays canonical" {
  @quickcheck.check(
    (t : WideTree) => {
      let canonical = @printer.print(t.statement)
      code_points(canonical) > t.width ||
      @printer.print(t.statement, width=t.width) == canonical
    },
    count=1000,
  )
}
