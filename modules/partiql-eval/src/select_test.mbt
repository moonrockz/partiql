///|
fn tuple(fields : Array[(String, @value.Value)]) -> @value.Value {
  @value.Value::from_tuple(@value.Tuple(fields))
}

///|
fn bag_of(items : Array[@value.Value]) -> @value.Value {
  @value.Value::from_bag(@value.Bag(items))
}

///|
test "SELECT forms" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT x.a, x.b AS c FROM [{'a': 1, 'b': 2}] AS x"))
    .to_equal(
      bag_of([
        tuple([
          ("a", @value.Value::from_int(1)),
          ("c", @value.Value::from_int(2)),
        ]),
      ]),
    )
    soft
    .expect(ev("SELECT i + 1 FROM <<100>> i"))
    .to_equal(bag_of([tuple([("_1", @value.Value::from_int(101))])]))
    soft
    .expect(ev("SELECT a.x AS x, a.y AS y FROM [{'x': 5}, {'y': 6}] AS a"))
    .to_equal(
      bag_of([
        tuple([("x", @value.Value::from_int(5))]),
        tuple([("y", @value.Value::from_int(6))]),
      ]),
    )
    soft
    .expect(ev("select x.someColumn from <<{'someColumn': MISSING}>> AS x"))
    .to_equal(bag_of([tuple([])]))
    soft
    .expect_call(() => {
      ev(
        "select x.someColumn from <<{'someColumn': MISSING}>> AS x",
        mode=Strict,
      )
    })
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    soft
    .expect(ev("SELECT * FROM <<{'a': 1}>>, <<{'b': 2}>>"))
    .to_equal(
      bag_of([
        tuple([
          ("a", @value.Value::from_int(1)),
          ("b", @value.Value::from_int(2)),
        ]),
      ]),
    )
    soft
    .expect(ev("SELECT * FROM <<{'a': 1}>> AS x, <<{'a': 2}>> AS y"))
    .to_equal(
      bag_of([
        tuple([
          ("a", @value.Value::from_int(1)),
          ("a", @value.Value::from_int(2)),
        ]),
      ]),
    )
    soft
    .expect(ev("SELECT x.* FROM [{'a': 1, 'b': 2}] AS x"))
    .to_equal(
      bag_of([
        tuple([
          ("a", @value.Value::from_int(1)),
          ("b", @value.Value::from_int(2)),
        ]),
      ]),
    )
    soft
    .expect(ev("SELECT DISTINCT VALUE x FROM [1, 1, 2] AS x"))
    .to_equal(bag_of([@value.Value::from_int(1), @value.Value::from_int(2)]))
    soft
    .expect(ev("SELECT VALUE y FROM [1, 2] AS x LET x * 10 AS y"))
    .to_equal(bag_of([@value.Value::from_int(10), @value.Value::from_int(20)]))
  })
}

///|
test "SELECT * over values that are not tuples" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT * FROM [ [1,2] ] as foo"))
    .to_equal(
      bag_of([
        tuple([
          (
            "_1",
            @value.Value::from_list([
              @value.Value::from_int(1),
              @value.Value::from_int(2),
            ]),
          ),
        ]),
      ]),
    )
    soft
    .expect(ev("SELECT * FROM << [1,2] >> as foo"))
    .to_equal(
      bag_of([
        tuple([
          (
            "_1",
            @value.Value::from_list([
              @value.Value::from_int(1),
              @value.Value::from_int(2),
            ]),
          ),
        ]),
      ]),
    )
    soft
    .expect(ev("SELECT * FROM <<{'someColumn': MISSING}>>"))
    .to_equal(bag_of([tuple([])]))
  })
}

///|
test "DISTINCT and LET" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT DISTINCT a FROM [{'a': 1}, {'a': 2}, {'a': 1}] AS t"))
    .to_equal(
      bag_of([
        tuple([("a", @value.Value::from_int(1))]),
        tuple([("a", @value.Value::from_int(2))]),
      ]),
    )
    soft
    .expect(
      ev("SELECT DISTINCT * FROM [{'a': 1, 'b': 1}, {'a': 2}, {'a': 1}] AS t"),
    )
    .to_equal(
      bag_of([
        tuple([
          ("a", @value.Value::from_int(1)),
          ("b", @value.Value::from_int(1)),
        ]),
        tuple([("a", @value.Value::from_int(2))]),
        tuple([("a", @value.Value::from_int(1))]),
      ]),
    )
    soft
    .expect(
      ev("SELECT DISTINCT VALUE x FROM [<<1, 2>>, <<2, 1>>, [1, 2]] AS x"),
    )
    .to_equal(
      bag_of([
        bag_of([@value.Value::from_int(1), @value.Value::from_int(2)]),
        @value.Value::from_list([
          @value.Value::from_int(1),
          @value.Value::from_int(2),
        ]),
      ]),
    )
    soft
    .expect(
      ev(
        "SELECT VALUE z FROM [1, 2] AS x LET x * 10 AS y, y + 1 AS z WHERE z > 11",
      ),
    )
    .to_equal(bag_of([@value.Value::from_int(21)]))
  })
}

///|
test "x.* over a value that is not a tuple" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(ev("SELECT x.* FROM [{'a':1}, 'foo'] AS x", mode~))
      .to_equal(
        bag_of([
          tuple([("a", @value.Value::from_int(1))]),
          tuple([("_1", @value.Value::from_string("foo"))]),
        ]),
      )
    }
  })
}

///|
test "a long LET list evaluates without overflowing the stack" {
  let lets = Array::makei(3000, i => "\{i} + 1 AS v\{i}")
  @expect.expect(ev("SELECT VALUE v2999 FROM [1] AS x LET " + lets.join(", "))).to_equal(
    bag_of([@value.Value::from_int(3000)]),
  )
}

///|
test "DISTINCT uses grouping equivalence" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT DISTINCT VALUE x FROM [1, 1.0, 1e0, 2] AS x"))
    .to_equal(bag_of([@value.Value::from_int(1), @value.Value::from_int(2)]))
    soft
    .expect(ev("SELECT DISTINCT VALUE x FROM [1.0, 1.00, 1] AS x"))
    .to_equal(bag_of([@value.Value::from_decimal(@ion.Decimal::parse("1.0"))]))
    soft
    .expect(ev("SELECT DISTINCT VALUE x FROM [[1], [1.0], [2]] AS x"))
    .to_equal(
      bag_of([
        @value.Value::from_list([@value.Value::from_int(1)]),
        @value.Value::from_list([@value.Value::from_int(2)]),
      ]),
    )
    soft
    .expect(ev("SELECT DISTINCT VALUE x FROM [NULL, NULL, MISSING] AS x"))
    .to_equal(bag_of([Null, Missing]))
  })
}

///|
test "DISTINCT over many values is not quadratic" {
  let lists = Array::makei(20000, i => "[\{i}]").join(",")
  let dates = Array::makei(20000, i => {
    "DATE '\{2000 + i / 18}-01-\{i % 18 + 10}'"
  })
  let tuples = Array::makei(20000, i => "{'a': \{i}, 'b': [\{i}]}")
  @expect.expect_all(soft => {
    match ev("SELECT DISTINCT VALUE x FROM [\{lists}] AS x") {
      Bag(b) => soft.expect(b.length()).to_equal(20000)
      _ => soft.expect(false).to_be_true()
    }
    match ev("SELECT DISTINCT VALUE x FROM [\{dates.join(",")}] AS x") {
      Bag(b) => soft.expect(b.length()).to_equal(20000)
      _ => soft.expect(false).to_be_true()
    }
    match ev("SELECT DISTINCT x.a FROM [\{tuples.join(",")}] AS x") {
      Bag(b) => soft.expect(b.length()).to_equal(20000)
      _ => soft.expect(false).to_be_true()
    }
  })
}
