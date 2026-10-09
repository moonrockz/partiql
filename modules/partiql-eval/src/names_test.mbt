///|
fn names_env() -> @eval.Bindings {
  let row1 = @value.Tuple::new([("a", Int(1)), ("b", Int(2))])
  let row2 = @value.Tuple::new([("a", Int(3))])
  @eval.Bindings::of_tuple(
    @value.Tuple::new([
      ("t", List([Tuple(row1), Tuple(row2)])),
      ("a", Int(100)),
      ("s", List([Tuple(@value.Tuple::new([("x", Int(1))]))])),
    ]),
  )
}

///|
fn names_ev(
  source : String,
  mode? : @eval.Mode = Permissive,
) -> @value.Value raise @eval.EvalError {
  @eval.evaluate_text(source, env=names_env(), mode~)
}

///|
test "names in queries" {
  @expect.expect_all(soft => {
    // a local variable wins over a global of the same name
    soft
    .expect(names_ev("SELECT VALUE a FROM [5] AS a"))
    .to_equal(bag([Int(5)]))
    // a global is visible inside a query; a variable's attribute wins
    soft
    .expect(names_ev("SELECT VALUE a FROM t AS r"))
    .to_equal(bag([Int(1), Int(3)]))
    soft
    .expect(names_ev("SELECT VALUE a FROM [{'b': 1}] AS r"))
    .to_equal(bag([Int(100)]))
    // an unbound name is an attribute of a FROM variable's tuple
    soft
    .expect(names_ev("SELECT VALUE b FROM t AS r"))
    .to_equal(bag([Int(2), Missing]))
    soft
    .expect_call(() => names_ev("SELECT VALUE b FROM t AS r", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    // @x takes locals only
    soft
    .expect(names_ev("SELECT VALUE @r.a FROM t AS r"))
    .to_equal(bag([Int(1), Int(3)]))
    // shadowing does not leak out of a subquery
    soft
    .expect(
      names_ev("SELECT VALUE [(SELECT VALUE a FROM [7] AS a), a] FROM [1] AS z"),
    )
    .to_equal(bag([List([bag([Int(7)]), Int(100)])]))
    // case-insensitive unless quoted
    soft
    .expect(names_ev("SELECT VALUE R.A FROM t AS r"))
    .to_equal(bag([Int(1), Int(3)]))
  })
}

///|
test "implicit attributes in FROM order" {
  @expect.expect_all(soft => {
    soft
    .expect(names_ev("SELECT VALUE x FROM [{'x': 1}] AS p, [{'x': 2}] AS q"))
    .to_equal(bag([Int(1)]))
    soft
    .expect(names_ev("SELECT VALUE y FROM [{'x': 1}] AS p, [{'y': 2}] AS q"))
    .to_equal(bag([Int(2)]))
    // an outer variable is reached from a subquery
    soft
    .expect(
      names_ev(
        "SELECT VALUE (SELECT VALUE x FROM [5] AS i) FROM [{'x': 9}] AS o",
      ),
    )
    .to_equal(bag([bag([Int(9)])]))
    // an ON clause sees the attributes of the variables declared so far
    soft
    .expect(
      names_ev(
        "SELECT VALUE y FROM [{'x': 1}] AS p JOIN [{'y': 2}] AS q ON y = x + 1",
      ),
    )
    .to_equal(bag([Int(2)]))
  })
}

///|
test "a name found nowhere" {
  @expect.expect_all(soft => {
    soft
    .expect(names_ev("SELECT VALUE nope FROM t AS r"))
    .to_equal(bag([Missing, Missing]))
    soft
    .expect_call(() => names_ev("SELECT VALUE nope FROM t AS r", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    // `@t` in the first source of a query is a variable, not the global `t`
    soft
    .expect_call(() => names_ev("SELECT VALUE 1 FROM @t"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    soft
    .expect_call(() => names_ev("SELECT VALUE 1 FROM [1] AS x, @t"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    // a delimited name matches an attribute of the same case only
    soft
    .expect(names_ev("SELECT VALUE \"X\" FROM [{'x': 1}] AS p"))
    .to_equal(bag([Missing]))
    soft
    .expect_call(() => names_ev("nope"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    soft
    .expect_call(() => names_ev("SELECT VALUE 1 FROM nope AS r"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    soft
    .expect_call(() => names_ev("SELECT VALUE @nope FROM t AS r"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
  })
}

///|
test "case and scope of implicit names" {
  @expect.expect_all(soft => {
    soft
    .expect(names_ev("SELECT VALUE X FROM [{'x': 1}] AS p"))
    .to_equal(bag([Int(1)]))
    soft
    .expect(names_ev("SELECT VALUE \"x\" FROM [{'x': 1}] AS p"))
    .to_equal(bag([Int(1)]))
    // a FROM-source subquery sees an outer variable
    soft
    .expect(
      names_ev(
        "SELECT VALUE v FROM [{'x': 4}] AS o, (SELECT VALUE x FROM [0] AS i) AS v",
      ),
    )
    .to_equal(bag([Int(4)]))
    // `@x` in a FROM source finds an earlier variable
    soft
    .expect(names_ev("SELECT VALUE y FROM [[1, 2]] AS x, @x AS y"))
    .to_equal(bag([Int(1), Int(2)]))
    // `@t` outside a query is unchanged
    soft.expect(names_ev("@a")).to_equal(Int(100))
  })
}

///|
test "implicit name: variable attribute before global" {
  let env = @eval.Bindings::of_tuple(
    @value.Tuple::new([("a", String("global-a"))]),
  )
  @expect.expect_all(soft => {
    soft
    .expect(@eval.evaluate_text("SELECT VALUE a FROM [{'a': 1}] AS x", env~))
    .to_equal(bag([Int(1)]))
    soft
    .expect(@eval.evaluate_text("SELECT VALUE a FROM [{'b': 1}] AS x", env~))
    .to_equal(bag([String("global-a")]))
  })
}

///|
test "a repeated FROM variable is an error" {
  let items = @value.Tuple::new([("items", List([Int(1)]))])
  let env = @eval.Bindings::of_tuple(
    @value.Tuple::new([
      ("s", Tuple(items)),
      ("u", Tuple(items)),
      ("t", List([Int(1)])),
    ]),
  )
  fn rejects(q : String, mode : @eval.Mode) -> (Bool, String) {
    try @eval.evaluate_text(q, env~, mode~) catch {
      @eval.EvalError::DataError(message~, ..) => (true, message)
      _ => (false, "")
    } noraise {
      _ => (false, "")
    }
  }

  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, @eval.Mode::Strict] {
      for
        q in [
          "SELECT * FROM [{'a':1}] AS x, [{'b':2}] AS x", "SELECT * FROM s.items, u.items",
          "SELECT * FROM t AS x AT x",
        ] {
        let (bad, message) = rejects(q, mode)
        soft.expect(bad).to_be_true()
        soft.expect(message).to_contain("AS")
      }
    }
    // LET and an inner query may shadow
    soft
    .expect(
      @eval.evaluate_text("SELECT VALUE x FROM [1] AS x LET 2 AS x", env~),
    )
    .to_equal(bag([Int(2)]))
    soft
    .expect(
      @eval.evaluate_text(
        "SELECT VALUE (SELECT VALUE x FROM [5] AS x) FROM [1] AS x",
        env~,
      ),
    )
    .to_equal(bag([bag([Int(5)])]))
  })
}
