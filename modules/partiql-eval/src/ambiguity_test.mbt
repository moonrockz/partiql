///|
test "same frame names with different spellings are statically ambiguous" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for
        (source, name, spellings) in [
          (
            "SELECT VALUE an_alias.f FROM [] AS an_alias, [] AS AN_ALIAS", "an_alias",
            "an_alias and AN_ALIAS",
          ),
          ("SELECT VALUE x FROM [] AS x AT X", "x", "x and X"),
          ("SELECT VALUE x FROM [] AS t LET 1 AS x, 2 AS X", "x", "x and X"),
          (
            "SELECT VALUE k FROM [] AS t GROUP BY t.a AS k, t.b AS K", "k", "k and K",
          ),
          (
            "SELECT VALUE k FROM [] AS t GROUP BY t.a AS k GROUP AS K", "k", "k and K",
          ),
          ("SELECT 1 AS x, 2 AS X FROM [] AS t ORDER BY x", "x", "x and X"),
          ("SELECT 1 AS x, 2 AS X FROM [] AS t ORDER BY x + 1", "x", "x and X"),
          (
            "WITH x AS (SELECT VALUE 1 FROM []), X AS (SELECT VALUE 2 FROM []) SELECT VALUE y FROM x AS y",
            "x", "x and X",
          ),
        ] {
        soft
        .expect_call(() => ev(source, mode~), label=source)
        .to_raise_matching(
          e => {
            e is @eval.EvalError::DataError(message~, span~) &&
            message ==
            "\{name} is ambiguous: it names \{spellings}; write the name in double quotes" &&
            source[span.start:span.end].to_owned() == name
          },
          description="static ambiguity at the identifier",
        )
      }
    }
  })
}

///|
test "quoted names and inner frames preserve shadowing" {
  let bag = (v : @value.Value) => @value.Value::Bag(@value.Bag::Bag([v]))
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(
        ev(
          "SELECT VALUE [\"an_alias\", \"AN_ALIAS\"] FROM [1] AS an_alias, [2] AS AN_ALIAS",
          mode~,
        ),
      )
      .to_equal(bag(List([Int(1), Int(2)])))
      soft
      .expect(
        ev("SELECT VALUE (SELECT VALUE x FROM [2] AS x) FROM [1] AS X", mode~),
      )
      .to_equal(bag(bag(Int(2))))
      soft
      .expect(ev("SELECT VALUE x FROM [0] AS t LET 1 AS x, 2 AS x", mode~))
      .to_equal(bag(Int(2)))
      soft
      .expect(
        ev(
          "SELECT VALUE [\"x\", \"X\"] FROM [0] AS t LET 1 AS x, 2 AS X",
          mode~,
        ),
      )
      .to_equal(bag(List([Int(1), Int(2)])))
      soft
      .expect(
        ev(
          "SELECT VALUE [\"k\", \"K\"] FROM [0] AS t GROUP BY 1 AS k, 2 AS K",
          mode~,
        ),
      )
      .to_equal(bag(List([Int(1), Int(2)])))
      soft
      .expect(
        ev(
          "WITH x AS (SELECT VALUE 1 FROM [0]), X AS (SELECT VALUE 2 FROM [0]) SELECT VALUE y FROM \"X\" AS y",
          mode~,
        ),
      )
      .to_equal(bag(Int(2)))
      soft
      .expect(ev("SELECT 1 AS x, 2 AS X FROM [0] AS t ORDER BY \"x\"", mode~))
      .to_equal(
        List([Tuple(@value.Tuple::Tuple([("x", Int(1)), ("X", Int(2))]))]),
      )
      // A non-bare sort key finds the variable before ambiguous output names.
      soft
      .expect(ev("SELECT 1 AS x, 2 AS X FROM [3] AS x ORDER BY x + 1", mode~))
      .to_equal(
        List([Tuple(@value.Tuple::Tuple([("x", Int(1)), ("X", Int(2))]))]),
      )
      // The innermost frame decides even when an outer frame is ambiguous.
      soft
      .expect(
        ev(
          "SELECT VALUE (SELECT VALUE x FROM [3] AS x) FROM [1] AS x, [2] AS X",
          mode~,
        ),
      )
      .to_equal(bag(bag(Int(3))))
    }
  })
}

///|
test "ambiguous globals are data errors at every lookup site" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for
        source in [
          "x", "SELECT VALUE x FROM [0] AS t", "SELECT VALUE v FROM [0] AS x, x AS v",
          "SELECT x FROM [1] AS t GROUP BY x",
        ] {
        soft
        .expect_call(
          () => ev_env(source, "{x:[1],X:[2],x:[3]}", mode~),
          label=source,
        )
        .to_raise_matching(
          e => {
            e
            is @eval.EvalError::DataError(
              message="x is ambiguous: it names x and X; write the name in double quotes",
              ..
            )
          },
          description="global ambiguity DataError",
        )
      }
    }
  })
}

///|
test "group key global precedence reports ambiguity at the identifier" {
  let source = "SELECT VALUE (SELECT VALUE y FROM x[0] AS y) FROM [[1]] AS x GROUP BY x[0] AS k"
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect_call(() => ev_env(source, "{x:[[7]],X:[[9]]}", mode~))
      .to_raise_matching(
        e => {
          e is @eval.EvalError::DataError(message~, span~) &&
          message ==
          "x is ambiguous: it names x and X; write the name in double quotes" &&
          source[span.start:span.end].to_owned() == "x"
        },
        description="global ambiguity at the identifier in a repeated key expression",
      )
    }
  })
}

///|
test "quoted globals and exact repeats preserve first binding and local precedence" {
  let bag = (v : @value.Value) => @value.Value::Bag(@value.Bag::Bag([v]))
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft.expect(ev_env("\"x\"", "{x:1,X:2,x:3}", mode~)).to_equal(Int(1))
      soft.expect(ev_env("\"X\"", "{x:1,X:2,x:3}", mode~)).to_equal(Int(2))
      soft.expect(ev_env("x", "{x:1,x:2}", mode~)).to_equal(Int(1))
      soft
      .expect(ev_env("SELECT VALUE x FROM [3] AS x", "{x:1,X:2}", mode~))
      .to_equal(bag(Int(3)))
      soft
      .expect(ev_env("SELECT VALUE x FROM [{'x':3}] AS t", "{x:1,X:2}", mode~))
      .to_equal(bag(Int(3)))
      soft
      .expect(ev_env("SELECT VALUE \"X\" FROM [0] AS t", "{x:1,X:2}", mode~))
      .to_equal(bag(Int(2)))
      // A bound MISSING still counts as the first global and as a spelling.
      let missing = @eval.Bindings::of_pairs([("x", Missing), ("X", Int(2))])
      soft
      .expect(@eval.evaluate_text("\"x\"", env=missing, mode~))
      .to_equal(Missing)
      soft
      .expect_call(() => @eval.evaluate_text("x", env=missing, mode~))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="ambiguous global with a MISSING value",
      )
    }
  })
}

///|
test "FROM sources find a global before ambiguous local spellings" {
  let source = "SELECT VALUE y FROM [1] AS x, [2] AS X, x AS y"
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(ev_env(source, "{x:[7]}", mode~))
      .to_equal(Bag(@value.Bag::Bag([Int(7)])))
    }
  })
}

///|
test "FROM source ambiguity uses the winning lookup tier" {
  let source = "SELECT VALUE y FROM [[1]] AS x, [[2]] AS X, x AS y"
  let bag = (v : @value.Value) => @value.Value::Bag(@value.Bag::Bag([v]))
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(
        ev_env("SELECT VALUE y FROM [] AS x, [] AS X, x AS y", "{}", mode~),
      )
      .to_equal(Bag(@value.Bag::Bag([])))
      soft
      .expect(
        ev_env(
          "SELECT VALUE y FROM [[1]] AS x, @x AS y",
          "{x:[7],X:[8]}",
          mode~,
        ),
      )
      .to_equal(bag(Int(1)))
      soft.expect(ev_env(source, "{X:[7]}", mode~)).to_equal(bag(Int(7)))
      soft.expect(ev_env(source, "{x:[7],x:[8]}", mode~)).to_equal(bag(Int(7)))
      for globals in ["{}", "{x:[7],X:[8]}"] {
        soft
        .expect_call(() => ev_env(source, globals, mode~), label=globals)
        .to_raise_matching(
          e => {
            e is @eval.EvalError::DataError(message~, span~) &&
            message ==
            "x is ambiguous: it names x and X; write the name in double quotes" &&
            source[span.start:span.end].to_owned() == "x"
          },
          description="ambiguity in the winning global or local tier",
        )
      }
      soft
      .expect(
        ev_env(
          "SELECT VALUE y FROM [[1]] AS x, [[2]] AS X, \"x\" AS y",
          "{}",
          mode~,
        ),
      )
      .to_equal(bag(Int(1)))
      soft
      .expect(
        ev_env(
          "SELECT VALUE y FROM [[1]] AS x, [[2]] AS X, \"X\" AS y",
          "{}",
          mode~,
        ),
      )
      .to_equal(bag(Int(2)))
      soft
      .expect(
        ev_env(
          "SELECT VALUE y FROM [[1]] AS x, [[2]] AS X, \"x\" AS y",
          "{x:[7]}",
          mode~,
        ),
      )
      .to_equal(bag(Int(7)))
      soft
      .expect_call(() => {
        ev_env(
          "SELECT VALUE y FROM [] AS x, [] AS X, @x AS y",
          "{x:[7]}",
          mode~,
        )
      })
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="qualified locals are statically ambiguous even over empty input",
      )
      soft
      .expect_call(() => {
        ev_env(
          "WITH x AS (SELECT VALUE 1 FROM [0]), X AS (SELECT VALUE 2 FROM [0]) SELECT VALUE y FROM x AS y",
          "{x:[7]}",
          mode~,
        )
      })
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="WITH ambiguity precedes globals",
      )
      soft
      .expect(
        ev_env(
          "WITH x AS (SELECT VALUE 1 FROM [0]) SELECT VALUE y FROM x AS y",
          "{x:[7],X:[8]}",
          mode~,
        ),
      )
      .to_equal(bag(Int(1)))
      soft
      .expect(
        ev_env(
          "SELECT VALUE (SELECT VALUE y FROM [[3]] AS x, x AS y) FROM [1] AS x, [2] AS X",
          "{}",
          mode~,
        ),
      )
      .to_equal(bag(bag(Int(3))))
      soft
      .expect(
        ev_env(
          "SELECT VALUE (SELECT VALUE y FROM [[3]] AS x, x AS y) FROM [1] AS x, [2] AS X",
          "{x:[7]}",
          mode~,
        ),
      )
      .to_equal(bag(bag(Int(7))))
    }
  })
}
