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
  let bag = (v : @value.Value) => @value.Value::from_bag(@value.Bag([v]))
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(
        ev(
          "SELECT VALUE [\"an_alias\", \"AN_ALIAS\"] FROM [1] AS an_alias, [2] AS AN_ALIAS",
          mode~,
        ),
      )
      .to_equal(
        bag(
          @value.Value::from_list([
            @value.Value::from_int(1),
            @value.Value::from_int(2),
          ]),
        ),
      )
      soft
      .expect(
        ev("SELECT VALUE (SELECT VALUE x FROM [2] AS x) FROM [1] AS X", mode~),
      )
      .to_equal(bag(bag(@value.Value::from_int(2))))
      soft
      .expect(ev("SELECT VALUE x FROM [0] AS t LET 1 AS x, 2 AS x", mode~))
      .to_equal(bag(@value.Value::from_int(2)))
      soft
      .expect(
        ev(
          "SELECT VALUE [\"x\", \"X\"] FROM [0] AS t LET 1 AS x, 2 AS X",
          mode~,
        ),
      )
      .to_equal(
        bag(
          @value.Value::from_list([
            @value.Value::from_int(1),
            @value.Value::from_int(2),
          ]),
        ),
      )
      soft
      .expect(
        ev(
          "SELECT VALUE [\"k\", \"K\"] FROM [0] AS t GROUP BY 1 AS k, 2 AS K",
          mode~,
        ),
      )
      .to_equal(
        bag(
          @value.Value::from_list([
            @value.Value::from_int(1),
            @value.Value::from_int(2),
          ]),
        ),
      )
      soft
      .expect(
        ev(
          "WITH x AS (SELECT VALUE 1 FROM [0]), X AS (SELECT VALUE 2 FROM [0]) SELECT VALUE y FROM \"X\" AS y",
          mode~,
        ),
      )
      .to_equal(bag(@value.Value::from_int(2)))
      soft
      .expect(ev("SELECT 1 AS x, 2 AS X FROM [0] AS t ORDER BY \"x\"", mode~))
      .to_equal(
        @value.Value::from_list([
          @value.Value::from_tuple(
            @value.Tuple([
              ("x", @value.Value::from_int(1)),
              ("X", @value.Value::from_int(2)),
            ]),
          ),
        ]),
      )
      // A non-bare sort key finds the variable before ambiguous output names.
      soft
      .expect(ev("SELECT 1 AS x, 2 AS X FROM [3] AS x ORDER BY x + 1", mode~))
      .to_equal(
        @value.Value::from_list([
          @value.Value::from_tuple(
            @value.Tuple([
              ("x", @value.Value::from_int(1)),
              ("X", @value.Value::from_int(2)),
            ]),
          ),
        ]),
      )
      // The innermost frame decides even when an outer frame is ambiguous.
      soft
      .expect(
        ev(
          "SELECT VALUE (SELECT VALUE x FROM [3] AS x) FROM [1] AS x, [2] AS X",
          mode~,
        ),
      )
      .to_equal(bag(bag(@value.Value::from_int(3))))
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
  let bag = (v : @value.Value) => @value.Value::from_bag(@value.Bag([v]))
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(ev_env("\"x\"", "{x:1,X:2,x:3}", mode~))
      .to_equal(@value.Value::from_int(1))
      soft
      .expect(ev_env("\"X\"", "{x:1,X:2,x:3}", mode~))
      .to_equal(@value.Value::from_int(2))
      soft
      .expect(ev_env("x", "{x:1,x:2}", mode~))
      .to_equal(@value.Value::from_int(1))
      soft
      .expect(ev_env("SELECT VALUE x FROM [3] AS x", "{x:1,X:2}", mode~))
      .to_equal(bag(@value.Value::from_int(3)))
      soft
      .expect(ev_env("SELECT VALUE x FROM [{'x':3}] AS t", "{x:1,X:2}", mode~))
      .to_equal(bag(@value.Value::from_int(3)))
      soft
      .expect(ev_env("SELECT VALUE \"X\" FROM [0] AS t", "{x:1,X:2}", mode~))
      .to_equal(bag(@value.Value::from_int(2)))
      // A bound MISSING still counts as the first global and as a spelling.
      let missing = @eval.Bindings::of_pairs([
        ("x", Missing),
        ("X", @value.Value::from_int(2)),
      ])
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
      .to_equal(@value.Value::from_bag(@value.Bag([@value.Value::from_int(7)])))
    }
  })
}

///|
test "FROM source ambiguity uses the winning lookup tier" {
  let source = "SELECT VALUE y FROM [[1]] AS x, [[2]] AS X, x AS y"
  let bag = (v : @value.Value) => @value.Value::from_bag(@value.Bag([v]))
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(
        ev_env("SELECT VALUE y FROM [] AS x, [] AS X, x AS y", "{}", mode~),
      )
      .to_equal(@value.Value::from_bag(@value.Bag([])))
      soft
      .expect(
        ev_env(
          "SELECT VALUE y FROM [[1]] AS x, @x AS y",
          "{x:[7],X:[8]}",
          mode~,
        ),
      )
      .to_equal(bag(@value.Value::from_int(1)))
      soft
      .expect(ev_env(source, "{X:[7]}", mode~))
      .to_equal(bag(@value.Value::from_int(7)))
      soft
      .expect(ev_env(source, "{x:[7],x:[8]}", mode~))
      .to_equal(bag(@value.Value::from_int(7)))
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
      .to_equal(bag(@value.Value::from_int(1)))
      soft
      .expect(
        ev_env(
          "SELECT VALUE y FROM [[1]] AS x, [[2]] AS X, \"X\" AS y",
          "{}",
          mode~,
        ),
      )
      .to_equal(bag(@value.Value::from_int(2)))
      soft
      .expect(
        ev_env(
          "SELECT VALUE y FROM [[1]] AS x, [[2]] AS X, \"x\" AS y",
          "{x:[7]}",
          mode~,
        ),
      )
      .to_equal(bag(@value.Value::from_int(7)))
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
      .to_equal(bag(@value.Value::from_int(1)))
      soft
      .expect(
        ev_env(
          "SELECT VALUE (SELECT VALUE y FROM [[3]] AS x, x AS y) FROM [1] AS x, [2] AS X",
          "{}",
          mode~,
        ),
      )
      .to_equal(bag(bag(@value.Value::from_int(3))))
      soft
      .expect(
        ev_env(
          "SELECT VALUE (SELECT VALUE y FROM [[3]] AS x, x AS y) FROM [1] AS x, [2] AS X",
          "{x:[7]}",
          mode~,
        ),
      )
      .to_equal(bag(bag(@value.Value::from_int(7))))
    }
  })
}

///|
test "implicit attributes reject matches in two FROM variables in both modes" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for
        source in [
          "SELECT VALUE x FROM [{'x':1}] AS t, [{'x':2}] AS u", "SELECT VALUE x FROM `[{x:1}]` AS t, `[{x:2}]` AS u",
          "SELECT VALUE x FROM [{'x':1}] AS t, [{'X':2}] AS u", "SELECT VALUE \"x\" FROM [{'x':1}] AS t, [{'x':2}] AS u",
        ] {
        soft
        .expect_call(() => ev(source, mode~), label=source)
        .to_raise_matching(
          e => {
            e is @eval.EvalError::DataError(message~, span~) &&
            message ==
            "attribute x is ambiguous: it occurs in t and u; qualify it with a variable name" &&
            source[span.start:span.end].to_owned() is ("x" | "\"x\"")
          },
          description="cross-variable ambiguity at the reference",
        )
      }
    }
  })
}

///|
test "implicit attribute lookup preserves scopes qualification and shadowing" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for
        (source, expected) in [
          (
            "SELECT VALUE [t.x,u.x] FROM [{'x':1}] AS t, [{'x':2}] AS u", "<<[1,2]>>",
          ),
          ("SELECT VALUE \"x\" FROM [{'x':1}] AS t, [{'X':2}] AS u", "<<1>>"),
          (
            "SELECT VALUE x FROM [0] AS t LET {'x':1} AS u, {'x':2} AS u", "<<2>>",
          ),
          (
            "SELECT VALUE (SELECT VALUE x FROM [{'x':2}] AS i) FROM [{'x':1}] AS o, [{'x':3}] AS p",
            "<<<<2>>>>",
          ),
          (
            "SELECT VALUE (SELECT VALUE x FROM [0] AS i) FROM [{'x':1}] AS o", "<<<<1>>>>",
          ),
          (
            "SELECT VALUE (SELECT VALUE x FROM [{'x':2}] AS o) FROM [{'x':1}] AS o",
            "<<<<2>>>>",
          ),
          (
            "SELECT VALUE (SELECT VALUE x FROM [0] AS o) FROM [{'x':1}] AS o, [{'x':3}] AS p",
            "<<<<3>>>>",
          ),
          ("SELECT VALUE x FROM [] AS t, [{'x':2}] AS u", "<<>>"),
          ("SELECT VALUE x FROM [{'x':null}] AS t, [{'y':2}] AS u", "<<null>>"),
        ] {
        soft.expect(ev(source, mode~), label=source).to_equal(ev(expected))
      }
      for
        source in [
          "SELECT VALUE (SELECT VALUE x FROM [0] AS i) FROM [{'x':1}] AS t, [{'x':2}] AS u",
          "SELECT VALUE x FROM [{'x':1,'x':2}] AS t, [{'x':3}] AS u", "SELECT VALUE x FROM [{'x':null}] AS t, [{'x':2}] AS u",
          "SELECT VALUE 1 FROM [{'x':1}] AS t JOIN [{'x':2}] AS u ON x = 1", "SELECT VALUE 1 FROM [{'x':1}] AS t, [{'x':2}] AS u WHERE x = 1",
          "SELECT VALUE 1 FROM [{'x':1}] AS t, [{'x':2}] AS u GROUP BY x",
        ] {
        soft
        .expect_call(() => ev_env(source, "{x:99}", mode~), label=source)
        .to_raise_matching(
          e => e is @eval.EvalError::DataError(..),
          description="ambiguity is not hidden by globals or by a field type failure",
        )
      }
    }
  })
}

///|
test "ORDER BY rejects one output name for distinct expressions" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for
        source in [
          "SELECT 1 AS x, 2 AS x FROM [] AS t ORDER BY x", "SELECT 1 AS x, 2 AS x FROM [0] AS t ORDER BY \"x\"",
          "SELECT 1 AS x, 2 AS x FROM [0] AS t ORDER BY x + 1", "SELECT t.a AS x, t.b AS x FROM [{'a':1,'b':1}] AS t ORDER BY x",
          "SELECT SUM(t.a) AS x, COUNT(*) AS x FROM [] AS t ORDER BY x",
        ] {
        soft
        .expect_call(() => ev(source, mode~), label=source)
        .to_raise_matching(
          e => {
            e is @eval.EvalError::DataError(message~, span~) &&
            message ==
            "output name x is ambiguous: different SELECT expressions use it; use distinct aliases" &&
            source[span.start:span.end].to_owned() is ("x" | "\"x\"")
          },
          description="static output-name ambiguity at the ORDER BY reference",
        )
      }
    }
  })
}

///|
test "ORDER BY preserves identical outputs and winning variable scopes" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for
        (source, expected) in [
          (
            "SELECT t.a, t.a FROM [{'a':2},{'a':1}] AS t ORDER BY a", "[{'a':1,'a':1},{'a':2,'a':2}]",
          ),
          (
            "SELECT t.a+1 AS x, (T.A+1) AS x FROM [{'a':1}] AS t ORDER BY x", "[{'x':2,'x':2}]",
          ),
          (
            "SELECT 1 AS x, 2 AS x FROM [3] AS x ORDER BY x + 1", "[{'x':1,'x':2}]",
          ),
          (
            "SELECT 1 AS x, 2 AS x FROM [{'a':1}] AS t ORDER BY t.a", "[{'x':1,'x':2}]",
          ),
          (
            "SELECT SUM(t.a) AS x, SUM(t.a) AS x FROM [{'a':2}] AS t ORDER BY x",
            "[{'x':2,'x':2}]",
          ),
          ("SELECT t.a, t.a FROM [] AS t ORDER BY a", "[]"),
          ("SELECT 1 AS x, 2 AS x FROM [0] AS t", "<<{'x':1,'x':2}>>"),
        ] {
        soft.expect(ev(source, mode~), label=source).to_equal(ev(expected))
      }
      let source = "SELECT 1 AS x, 2 AS x FROM [0] AS t ORDER BY (SELECT VALUE y FROM x AS y)"
      soft
      .expect(ev_env(source, "{x:[9]}", mode~))
      .to_equal(ev("[{'x':1,'x':2}]"))
      soft
      .expect_call(() => ev_env(source, "{}", mode~))
      .to_raise_matching(
        e => {
          e
          is @eval.EvalError::DataError(
            message="output name x is ambiguous: different SELECT expressions use it; use distinct aliases",
            ..
          )
        },
        description="deferred output ambiguity when a FROM source has no matching global",
      )
    }
  })
}

///|
test "MISSING fields are absent and do not create implicit ambiguity" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(
        ev("SELECT VALUE x FROM [{'x':missing}] AS t, [{'x':2}] AS u", mode~),
      )
      .to_equal(ev("<<2>>"))
    }
  })
}

///|
test "implicit candidates mask outer names case-insensitively but keep same-scope spellings" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for
        source in [
          "SELECT VALUE (SELECT VALUE a FROM [0] AS T) FROM [{'a':1}] AS t", "SELECT VALUE (SELECT VALUE \"a\" FROM [0] AS T) FROM [{'a':1}] AS t",
          "SELECT VALUE (SELECT VALUE a FROM [0] AS T) FROM [{'a':1}] AS t, [{'a':2}] AS T",
        ] {
        soft
        .expect(ev_env(source, "{a:9}", mode~), label=source)
        .to_equal(ev("<<<<9>>>>"))
        match mode {
          Permissive =>
            soft
            .expect(ev(source), label=source)
            .to_equal(ev("<<<<missing>>>>"))
          Strict =>
            soft
            .expect_call(() => ev(source, mode~), label=source)
            .to_raise_matching(
              e => e is @eval.EvalError::TypeError(..),
              description="shadowed outer attribute is unavailable",
            )
        }
      }
      soft
      .expect_call(() => {
        ev("SELECT VALUE a FROM [{'a':1}] AS t, [{'a':2}] AS T", mode~)
      })
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="same-frame t and T remain two candidates",
      )
      soft
      .expect(
        ev(
          "SELECT VALUE [\"t\".a, \"T\".a] FROM [{'a':1}] AS t, [{'a':2}] AS T",
          mode~,
        ),
      )
      .to_equal(ev("<<[1,2]>>"))
      // A delimited variable reference still explicitly names the outer spelling.
      soft
      .expect(
        ev(
          "SELECT VALUE (SELECT VALUE \"t\".a FROM [0] AS T) FROM [{'a':1}] AS t",
          mode~,
        ),
      )
      .to_equal(ev("<<<<1>>>>"))
    }
  })
}
