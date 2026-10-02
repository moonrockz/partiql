///|
fn round_trips(s : @ast.Statement) -> Bool {
  let printed = @printer.print(s)
  try @parser.parse_statement(printed) catch {
    _ => false
  } noraise {
    back =>
      back.strip_spans() == s.strip_spans() && @printer.print(back) == printed
  }
}

///|
test "law 1: random statements round-trip" {
  @quickcheck.check((t : TreeSpec) => round_trips(t.statement), count=500)
}

///|
test "law 1: random expressions round-trip" {
  @quickcheck.check(
    (e : ExprSpec) => {
      let s : @ast.Statement = Query(
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
      round_trips(s)
    },
    count=1000,
  )
}
