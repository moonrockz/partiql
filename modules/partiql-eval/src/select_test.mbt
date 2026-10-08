///|
fn tuple(fields : Array[(String, @value.Value)]) -> @value.Value {
  @value.Value::Tuple(@value.Tuple::new(fields))
}

///|
fn bag_of(items : Array[@value.Value]) -> @value.Value {
  @value.Value::Bag(@value.Bag::new(items))
}

///|
test "SELECT forms" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT x.a, x.b AS c FROM [{'a': 1, 'b': 2}] AS x"))
    .to_equal(bag_of([tuple([("a", Int(1)), ("c", Int(2))])]))
    soft
    .expect(ev("SELECT i + 1 FROM <<100>> i"))
    .to_equal(bag_of([tuple([("_1", Int(101))])]))
    soft
    .expect(ev("SELECT a.x AS x, a.y AS y FROM [{'x': 5}, {'y': 6}] AS a"))
    .to_equal(bag_of([tuple([("x", Int(5))]), tuple([("y", Int(6))])]))
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
    .to_equal(bag_of([tuple([("a", Int(1)), ("b", Int(2))])]))
    soft
    .expect(ev("SELECT * FROM <<{'a': 1}>> AS x, <<{'a': 2}>> AS y"))
    .to_equal(bag_of([tuple([("a", Int(1)), ("a", Int(2))])]))
    soft
    .expect(ev("SELECT x.* FROM [{'a': 1, 'b': 2}] AS x"))
    .to_equal(bag_of([tuple([("a", Int(1)), ("b", Int(2))])]))
    soft
    .expect(ev("SELECT DISTINCT VALUE x FROM [1, 1, 2] AS x"))
    .to_equal(bag_of([Int(1), Int(2)]))
    soft
    .expect(ev("SELECT VALUE y FROM [1, 2] AS x LET x * 10 AS y"))
    .to_equal(bag_of([Int(10), Int(20)]))
  })
}

///|
test "SELECT * over values that are not tuples" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT * FROM [ [1,2] ] as foo"))
    .to_equal(bag_of([tuple([("_1", List([Int(1), Int(2)]))])]))
    soft
    .expect(ev("SELECT * FROM << [1,2] >> as foo"))
    .to_equal(bag_of([tuple([("_1", List([Int(1), Int(2)]))])]))
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
    .to_equal(bag_of([tuple([("a", Int(1))]), tuple([("a", Int(2))])]))
    soft
    .expect(
      ev("SELECT DISTINCT * FROM [{'a': 1, 'b': 1}, {'a': 2}, {'a': 1}] AS t"),
    )
    .to_equal(
      bag_of([
        tuple([("a", Int(1)), ("b", Int(1))]),
        tuple([("a", Int(2))]),
        tuple([("a", Int(1))]),
      ]),
    )
    soft
    .expect(
      ev("SELECT DISTINCT VALUE x FROM [<<1, 2>>, <<2, 1>>, [1, 2]] AS x"),
    )
    .to_equal(bag_of([bag_of([Int(1), Int(2)]), List([Int(1), Int(2)])]))
    soft
    .expect(
      ev(
        "SELECT VALUE z FROM [1, 2] AS x LET x * 10 AS y, y + 1 AS z WHERE z > 11",
      ),
    )
    .to_equal(bag_of([Int(21)]))
  })
}

///|
test "x.* over a value that is not a tuple" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(ev("SELECT x.* FROM [{'a':1}, 'foo'] AS x", mode~))
      .to_equal(
        bag_of([tuple([("a", Int(1))]), tuple([("_1", String("foo"))])]),
      )
    }
  })
}

///|
test "a long LET list evaluates without overflowing the stack" {
  let lets = Array::makei(3000, i => "\{i} + 1 AS v\{i}")
  @expect.expect(ev("SELECT VALUE v2999 FROM [1] AS x LET " + lets.join(", "))).to_equal(
    bag_of([Int(3000)]),
  )
}
