///|
fn vals(xs : Array[@value.Value]) -> Iter[@value.Value] {
  xs.iter()
}

///|
fn failure(f : () -> @value.Value raise OpFailure) -> String {
  try f() catch {
    TypeFailure(_) => "type"
    DataFailure(_) => "data"
  } noraise {
    _ => "none"
  }
}

///|
test "aggregates skip NULL and MISSING; empty input" {
  let absent : Array[@value.Value] = [Null, Missing]
  @expect.expect_all(soft => {
    soft.expect(count_values(vals(absent), distinct=false)).to_equal(Int(0))
    soft.expect(sum_values(vals(absent), distinct=false)).to_equal(Null)
    soft.expect(avg_values(vals([]), distinct=false)).to_equal(Null)
    soft.expect(min_values(vals(absent), distinct=false)).to_equal(Null)
    soft.expect(max_values(vals([]), distinct=false)).to_equal(Null)
    soft.expect(any_values(vals(absent), distinct=false)).to_equal(Null)
    soft.expect(every_values(vals([]), distinct=false)).to_equal(Null)
    soft
    .expect(
      count_values(vals([Int(1), Null, String("a"), Missing]), distinct=false),
    )
    .to_equal(Int(2))
  })
}

///|
test "SUM and AVG result types follow the corpus" {
  let ints : Array[@value.Value] = [Int(1), Int(1), Int(1), Int(2)]
  let mixed : Array[@value.Value] = [
    Int(1),
    w(dec("2.0")),
    Float(3.0),
    Int(4),
    w(dec("5.")),
  ]
  @expect.expect_all(soft => {
    soft.expect(sum_values(vals(ints), distinct=false)).to_equal(Int(5))
    soft.expect(avg_values(vals(ints), distinct=false)).to_equal(w(dec("1.25")))
    soft.expect(avg_values(vals(ints), distinct=true)).to_equal(w(dec("1.5")))
    soft
    .expect(avg_values(vals([Int(37), Int(37)]), distinct=false))
    .to_equal(w(dec("37.")))
    soft
    .expect(sum_values(vals(mixed), distinct=false))
    .to_equal(w(dec("15.0")))
    soft.expect(avg_values(vals(mixed), distinct=false)).to_equal(w(dec("3.0")))
    soft
    .expect(
      sum_values(
        vals([
          w(dec("1.0")),
          w(dec("2.0")),
          w(dec("3.0")),
          w(dec("4.0")),
          w(dec("5.0")),
        ]),
        distinct=false,
      ),
    )
    .to_equal(w(dec("15.0")))
  })
}

///|
test "SUM checks the integer range once, at the end" {
  let max : @value.Value = Int(9223372036854775807L)
  @expect.expect_all(soft => {
    soft
    .expect(sum_values(vals([max, Int(1), Int(-1)]), distinct=false))
    .to_equal(max)
    soft
    .expect(failure(() => sum_values(vals([max, Int(1)]), distinct=false)))
    .to_equal("data")
    soft
    .expect(failure(() => sum_values(vals([Float(0.0 / 0.0)]), distinct=false)))
    .to_equal("data")
    soft
    .expect(
      failure(() => {
        avg_values(vals([w(dec("1")), Float(1.0 / 0.0)]), distinct=false)
      }),
    )
    .to_equal("data")
  })
}

///|
test "DISTINCT uses grouping equivalence" {
  @expect.expect_all(soft => {
    soft
    .expect(count_values(vals([Int(1), w(dec("1.0")), Int(2)]), distinct=true))
    .to_equal(Int(2))
    soft
    .expect(sum_values(vals([Int(10), Int(1), Int(10), Int(3)]), distinct=true))
    .to_equal(Int(14))
  })
}

///|
test "MIN and MAX use the total order over any types" {
  let xs : Array[@value.Value] = [Int(1), String("non-number"), Null, Missing]
  @expect.expect_all(soft => {
    soft
    .expect(max_values(vals(xs), distinct=false))
    .to_equal(String("non-number"))
    soft.expect(min_values(vals(xs), distinct=false)).to_equal(Int(1))
    soft
    .expect(max_values(vals([Int(2), w(dec("5."))]), distinct=false))
    .to_equal(w(dec("5.")))
  })
}

///|
test "wrong element types are type failures" {
  @expect.expect_all(soft => {
    soft
    .expect(
      failure(() => sum_values(vals([Int(1), String("x")]), distinct=false)),
    )
    .to_equal("type")
    soft
    .expect(failure(() => avg_values(vals([Bool(true)]), distinct=false)))
    .to_equal("type")
    soft
    .expect(
      failure(() => any_values(vals([Bool(true), Int(5)]), distinct=false)),
    )
    .to_equal("type")
    soft
    .expect(any_values(vals([Bool(false), Null, Bool(true)]), distinct=false))
    .to_equal(Bool(true))
    soft
    .expect(
      every_values(
        vals([Null, Bool(true), Missing, Bool(true)]),
        distinct=false,
      ),
    )
    .to_equal(Bool(true))
    soft
    .expect(every_values(vals([Bool(true), Bool(false)]), distinct=false))
    .to_equal(Bool(false))
  })
}

///|
test "boxed Ion values act as the values they stand for" {
  let null_int = @value.Value::Ion(@ion_core.IonValue::typed_null(Int))
  let three = @value.Value::Ion(@ion_core.IonValue::int(3))
  @expect.expect_all(soft => {
    soft
    .expect(count_values(vals([null_int, three, Int(1)]), distinct=false))
    .to_equal(Int(2))
    soft
    .expect(sum_values(vals([null_int, three, Int(1)]), distinct=false))
    .to_equal(Int(4))
    soft
    .expect(count_values(vals([three, Int(3)]), distinct=true))
    .to_equal(Int(1))
    soft
    .expect(max_values(vals([three, Int(1)]), distinct=false))
    .to_equal(Int(3))
    soft.expect(sum_values(vals([null_int]), distinct=false)).to_equal(Null)
  })
}
