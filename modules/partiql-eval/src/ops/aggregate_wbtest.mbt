///|
fn vals(xs : Array[@value.Value]) -> Iter[@value.Value] {
  xs.iter()
}

///|
fn failure(f : () -> @value.Value raise OpFailure) -> String {
  try f() catch {
    TypeFailure(_) => "type"
    DataFailure(_) => "data"
    Unsupported(_) => "unsupported"
  } noraise {
    _ => "none"
  }
}

///|
test "aggregates skip NULL and MISSING; empty input" {
  let absent : Array[@value.Value] = [Null, Missing]
  @expect.expect_all(soft => {
    soft
    .expect(count_values(vals(absent), distinct=false))
    .to_equal(@value.Value::from_int(0))
    soft.expect(sum_values(vals(absent), distinct=false)).to_equal(Null)
    soft.expect(avg_values(vals([]), distinct=false)).to_equal(Null)
    soft.expect(min_values(vals(absent), distinct=false)).to_equal(Null)
    soft.expect(max_values(vals([]), distinct=false)).to_equal(Null)
    soft.expect(any_values(vals(absent), distinct=false)).to_equal(Null)
    soft.expect(every_values(vals([]), distinct=false)).to_equal(Null)
    soft
    .expect(
      count_values(
        vals([
          @value.Value::from_int(1),
          Null,
          @value.Value::from_string("a"),
          Missing,
        ]),
        distinct=false,
      ),
    )
    .to_equal(@value.Value::from_int(2))
  })
}

///|
test "SUM and AVG result types follow the corpus" {
  let ints : Array[@value.Value] = [
    @value.Value::from_int(1),
    @value.Value::from_int(1),
    @value.Value::from_int(1),
    @value.Value::from_int(2),
  ]
  let mixed : Array[@value.Value] = [
    @value.Value::from_int(1),
    w(dec("2.0")),
    @value.Value::from_float(3.0),
    @value.Value::from_int(4),
    w(dec("5.")),
  ]
  @expect.expect_all(soft => {
    soft
    .expect(sum_values(vals(ints), distinct=false))
    .to_equal(@value.Value::from_int(5))
    soft.expect(avg_values(vals(ints), distinct=false)).to_equal(w(dec("1.25")))
    soft.expect(avg_values(vals(ints), distinct=true)).to_equal(w(dec("1.5")))
    soft
    .expect(
      avg_values(
        vals([@value.Value::from_int(37), @value.Value::from_int(37)]),
        distinct=false,
      ),
    )
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
  let max : @value.Value = @value.Value::from_int(9223372036854775807L)
  @expect.expect_all(soft => {
    soft
    .expect(
      sum_values(
        vals([max, @value.Value::from_int(1), @value.Value::from_int(-1)]),
        distinct=false,
      ),
    )
    .to_equal(max)
    soft
    .expect(
      failure(() => {
        sum_values(vals([max, @value.Value::from_int(1)]), distinct=false)
      }),
    )
    .to_equal("data")
    soft
    .expect(
      failure(() => {
        sum_values(vals([@value.Value::from_float(0.0 / 0.0)]), distinct=false)
      }),
    )
    .to_equal("data")
    soft
    .expect(
      failure(() => {
        avg_values(
          vals([w(dec("1")), @value.Value::from_float(1.0 / 0.0)]),
          distinct=false,
        )
      }),
    )
    .to_equal("data")
  })
}

///|
test "DISTINCT uses grouping equivalence" {
  @expect.expect_all(soft => {
    soft
    .expect(
      count_values(
        vals([
          @value.Value::from_int(1),
          w(dec("1.0")),
          @value.Value::from_int(2),
        ]),
        distinct=true,
      ),
    )
    .to_equal(@value.Value::from_int(2))
    soft
    .expect(
      sum_values(
        vals([
          @value.Value::from_int(10),
          @value.Value::from_int(1),
          @value.Value::from_int(10),
          @value.Value::from_int(3),
        ]),
        distinct=true,
      ),
    )
    .to_equal(@value.Value::from_int(14))
  })
}

///|
test "MIN and MAX use the total order over any types" {
  let xs : Array[@value.Value] = [
    @value.Value::from_int(1),
    @value.Value::from_string("non-number"),
    Null,
    Missing,
  ]
  @expect.expect_all(soft => {
    soft
    .expect(max_values(vals(xs), distinct=false))
    .to_equal(@value.Value::from_string("non-number"))
    soft
    .expect(min_values(vals(xs), distinct=false))
    .to_equal(@value.Value::from_int(1))
    soft
    .expect(
      max_values(
        vals([@value.Value::from_int(2), w(dec("5."))]),
        distinct=false,
      ),
    )
    .to_equal(w(dec("5.")))
  })
}

///|
test "wrong element types are type failures" {
  @expect.expect_all(soft => {
    soft
    .expect(
      failure(() => {
        sum_values(
          vals([@value.Value::from_int(1), @value.Value::from_string("x")]),
          distinct=false,
        )
      }),
    )
    .to_equal("type")
    soft
    .expect(
      failure(() => {
        avg_values(vals([@value.Value::from_bool(true)]), distinct=false)
      }),
    )
    .to_equal("type")
    soft
    .expect(
      failure(() => {
        any_values(
          vals([@value.Value::from_bool(true), @value.Value::from_int(5)]),
          distinct=false,
        )
      }),
    )
    .to_equal("type")
    soft
    .expect(
      any_values(
        vals([
          @value.Value::from_bool(false),
          Null,
          @value.Value::from_bool(true),
        ]),
        distinct=false,
      ),
    )
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(
      every_values(
        vals([
          Null,
          @value.Value::from_bool(true),
          Missing,
          @value.Value::from_bool(true),
        ]),
        distinct=false,
      ),
    )
    .to_equal(@value.Value::from_bool(true))
    soft
    .expect(
      every_values(
        vals([@value.Value::from_bool(true), @value.Value::from_bool(false)]),
        distinct=false,
      ),
    )
    .to_equal(@value.Value::from_bool(false))
  })
}

///|
test "boxed Ion values act as the values they stand for" {
  let null_int = @value.Value::from_ion(@ion_core.IonValue::typed_null(Int))
  let three = @value.Value::from_ion(@ion_core.IonValue::int(3))
  @expect.expect_all(soft => {
    soft
    .expect(
      count_values(
        vals([null_int, three, @value.Value::from_int(1)]),
        distinct=false,
      ),
    )
    .to_equal(@value.Value::from_int(2))
    soft
    .expect(
      sum_values(
        vals([null_int, three, @value.Value::from_int(1)]),
        distinct=false,
      ),
    )
    .to_equal(@value.Value::from_int(4))
    soft
    .expect(
      count_values(vals([three, @value.Value::from_int(3)]), distinct=true),
    )
    .to_equal(@value.Value::from_int(1))
    soft
    .expect(
      max_values(vals([three, @value.Value::from_int(1)]), distinct=false),
    )
    .to_equal(@value.Value::from_int(3))
    soft.expect(sum_values(vals([null_int]), distinct=false)).to_equal(Null)
  })
}
