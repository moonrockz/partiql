///|
fn bag(items : Array[@value.Value]) -> @value.Value {
  Bag(@value.Bag::new(items))
}

///|
test "FROM forms" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE [i, v] FROM [10, 20] AS v AT i"))
    .to_equal(bag([List([Int(0), Int(10)]), List([Int(1), Int(20)])]))
    soft
    .expect(ev("SELECT VALUE i IS MISSING FROM <<10>> AS v AT i"))
    .to_equal(bag([Bool(true)]))
    soft
    .expect(ev("SELECT VALUE [k, v] FROM UNPIVOT {'a': 1, 'b': 2} AS v AT k"))
    .to_equal(bag([List([String("a"), Int(1)]), List([String("b"), Int(2)])]))
    soft
    .expect(ev("SELECT VALUE [x, y] FROM [1, 2] AS x, [10] AS y"))
    .to_equal(bag([List([Int(1), Int(10)]), List([Int(2), Int(10)])]))
    soft
    .expect(ev("SELECT VALUE [x, y] FROM [[1, 2]] AS x, x AS y"))
    .to_equal(
      bag([
        List([List([Int(1), Int(2)]), Int(1)]),
        List([List([Int(1), Int(2)]), Int(2)]),
      ]),
    )
    soft
    .expect(
      ev("SELECT VALUE [x, y] FROM [1, 2] AS x JOIN [2, 3] AS y ON x = y"),
    )
    .to_equal(bag([List([Int(2), Int(2)])]))
    soft
    .expect(
      ev("SELECT VALUE [x, y] FROM [1, 2] AS x LEFT JOIN [2] AS y ON x = y"),
    )
    .to_equal(bag([List([Int(1), Null]), List([Int(2), Int(2)])]))
    soft
    .expect(ev("SELECT VALUE [x, y] FROM [1] AS x LEFT JOIN [] AS y ON TRUE"))
    .to_equal(bag([List([Int(1), Null])]))
    soft
    .expect(ev("SELECT VALUE [x, y] FROM [1] AS x INNER JOIN [] AS y ON TRUE"))
    .to_equal(bag([]))
    soft
    .expect(
      ev("SELECT VALUE [x, y] FROM [1] AS x RIGHT JOIN [1, 2] AS y ON x = y"),
    )
    .to_equal(bag([List([Int(1), Int(1)]), List([Null, Int(2)])]))
    soft
    .expect_call(() => {
      ev("SELECT VALUE x FROM [1] AS x FULL JOIN [1] AS y ON TRUE")
    })
    .to_raise_matching(
      e => e is @eval.EvalError::Unsupported(..),
      description="Unsupported",
    )
  })
}

///|
test "FROM forms in strict mode" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE [x, y] FROM [1, 2] AS x, [10] AS y", mode=Strict))
    .to_equal(bag([List([Int(1), Int(10)]), List([Int(2), Int(10)])]))
    soft
    .expect(
      ev("SELECT VALUE [k, v] FROM UNPIVOT {'a': 1} AS v AT k", mode=Strict),
    )
    .to_equal(bag([List([String("a"), Int(1)])]))
    soft
    .expect_call(() => ev("SELECT VALUE v FROM UNPIVOT 1 AS v", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    soft
    .expect_call(() => ev("SELECT VALUE v FROM <<1>> AS v AT i", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}

///|
test "UNPIVOT of a value that is not a tuple" {
  // No corpus case: a non-tuple is the tuple {'_1': value} (spec section
  // 5.2), in permissive mode.
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE [k, v] FROM UNPIVOT 1 AS v AT k"))
    .to_equal(bag([List([String("_1"), Int(1)])]))
    soft
    .expect(ev("SELECT VALUE v FROM UNPIVOT {'a': 1, 'a': 2} AS v"))
    .to_equal(bag([Int(1), Int(2)]))
  })
}

///|
test "lateral sources and the padding of outer joins" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE [v1, v2] FROM 1 AS v1, @v1 AS v2"))
    .to_equal(bag([List([Int(1), Int(1)])]))
    // LEFT CROSS JOIN pads when the right side is empty.
    soft
    .expect(
      ev("SELECT VALUE [x, y] FROM [[1], []] AS x LEFT CROSS JOIN x AS y"),
    )
    .to_equal(bag([List([List([Int(1)]), Int(1)]), List([List([]), Null])]))
    // Both AS and AT of the right side are padded.
    soft
    .expect(
      ev("SELECT VALUE [y, j] FROM [1] AS x LEFT JOIN [] AS y AT j ON TRUE"),
    )
    .to_equal(bag([List([Null, Null])]))
    // The ON clause sees the variable of its own right side, not later ones.
    soft
    .expect(
      ev(
        "SELECT VALUE [a, b, d] FROM [1, 3] AS a INNER JOIN [1, 2, 3] AS b ON b < 3 LEFT JOIN [1.1, 2.1] AS d ON b < d AND a <= d",
        mode=Strict,
      ),
    )
    .to_equal(
      bag([
        List([Int(1), Int(1), Decimal(@ion.Decimal::parse("1.1"))]),
        List([Int(1), Int(1), Decimal(@ion.Decimal::parse("2.1"))]),
        List([Int(1), Int(2), Decimal(@ion.Decimal::parse("2.1"))]),
        List([Int(3), Int(1), Null]),
        List([Int(3), Int(2), Null]),
      ]),
    )
  })
}

///|
test "parenthesized joins and long lists" {
  @expect.expect_all(soft => {
    soft
    .expect(
      ev("SELECT VALUE [x, y, z] FROM ([1] AS x CROSS JOIN [2] AS y), [3] AS z"),
    )
    .to_equal(bag([List([Int(1), Int(2), Int(3)])]))
    soft
    .expect(
      ev("SELECT VALUE [x, y, z] FROM [1] AS x, ([2] AS y CROSS JOIN [3] AS z)"),
    )
    .to_equal(bag([List([Int(1), Int(2), Int(3)])]))
  })
}

///|
test "a plain name in a FROM source finds a global before a variable" {
  // select.ion, joinWithShadowedGlobal: `a` is a global, so `a.b` is the
  // global's attribute; `@a.b` is the variable's.
  let a = @value.Tuple::new([("b", @value.Value::Int(7))])
  let env = @eval.Bindings::of_tuple(
    @value.Tuple::new([("a", @value.Value::Tuple(a))]),
  )
  @expect.expect_all(soft => {
    soft
    .expect(
      @eval.evaluate_text(
        "SELECT VALUE b FROM [{'b':5}] AS a, a.b AS b",
        env~,
        mode=Permissive,
      ),
    )
    .to_equal(bag([Int(7)]))
    soft
    .expect(
      @eval.evaluate_text(
        "SELECT VALUE b FROM [{'b':5}] AS a, @a.b AS b",
        env~,
        mode=Permissive,
      ),
    )
    .to_equal(bag([Int(5)]))
  })
}

///|
fn long_from(n : Int, sep : String, on? : String = "") -> String {
  let items = Array::makei(n, i => {
    "[" + i.to_string() + "] AS v" + i.to_string()
  })
  let mut text = "SELECT VALUE v" + (n - 1).to_string() + " FROM " + items[0]
  for i = 1; i < n; i = i + 1 {
    text = text + sep + items[i] + on
  }
  text
}

///|
test "a FROM list of 10000 items" {
  // The joins of a chain run as one flat loop: no stack per item.
  @expect.expect_all(soft => {
    soft.expect(ev(long_from(10000, ", "))).to_equal(bag([Int(9999)]))
    soft.expect(ev(long_from(10000, " CROSS JOIN "))).to_equal(bag([Int(9999)]))
    soft
    .expect(ev(long_from(10000, " INNER JOIN ", on=" ON TRUE")))
    .to_equal(bag([Int(9999)]))
  })
}

///|
test "a FROM list with an ON in every join" {
  let items = Array::makei(3000, i => {
    "[" + i.to_string() + "] AS v" + i.to_string()
  })
  let mut text = "SELECT VALUE v2999 FROM " + items[0]
  for i = 1; i < 3000; i = i + 1 {
    text = text + " LEFT JOIN " + items[i] + " ON TRUE"
  }
  @expect.expect(ev(text)).to_equal(bag([Int(2999)]))
}

///|
test "right joins nest, and the depth guard bounds them" {
  let mut text = "SELECT VALUE v FROM [1] AS v"
  for _ in 0..<300 {
    text = text + " RIGHT JOIN [1] AS w ON TRUE"
  }
  @expect.expect_call(() => ev(text)).to_raise_matching(
    e => e is @eval.EvalError::DataError(..),
    description="DataError",
  )
}

///|
test "UNPIVOT of MISSING and of a map" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("SELECT VALUE v FROM UNPIVOT MISSING AS v AT k"))
    .to_equal(bag([]))
    soft
    .expect(ev("SELECT VALUE [k, v] FROM MISSING AS m, UNPIVOT m AS v AT k"))
    .to_equal(bag([]))
    soft
    .expect_call(() => {
      ev("SELECT VALUE v FROM UNPIVOT MISSING AS v", mode=Strict)
    })
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    soft
    .expect(ev("SELECT VALUE [k, v] FROM UNPIVOT NULL AS v AT k"))
    .to_equal(bag([List([String("_1"), Null])]))
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect(
        ev(
          "SELECT VALUE [k, v] FROM UNPIVOT MAP { 1: 'one', 2: 'two' } AS v AT k",
          mode~,
        ),
      )
      .to_equal(
        bag([List([Int(1), String("one")]), List([Int(2), String("two")])]),
      )
      soft
      .expect(ev("SELECT VALUE [k, v] FROM UNPIVOT MAP { } AS v AT k", mode~))
      .to_equal(bag([]))
      soft
      .expect(
        ev(
          "SELECT VALUE [k, v] FROM UNPIVOT MAP { TRUE: 'yes' } AS v AT k",
          mode~,
        ),
      )
      .to_equal(bag([List([Bool(true), String("yes")])]))
    }
  })
}

///|
/// Level `d` is `[1] AS a_d RIGHT JOIN (level d+1) ON TRUE`, then `198 - d`
/// more RIGHT JOINs: the nesting of right joins at run time is the sum.
fn nested_rights(levels : Int) -> String {
  let mut text = "[1] AS z CROSS JOIN [1] AS y"
  for d = levels - 1; d >= 0; d = d - 1 {
    let mut level = "[1] AS a" +
      d.to_string() +
      " RIGHT JOIN (" +
      text +
      ") ON TRUE"
    for _ in 0..<(198 - d) {
      level = level + " RIGHT JOIN [1] AS w" + d.to_string() + " ON TRUE"
    }
    text = level
  }
  "SELECT VALUE z FROM " + text
}

///|
test "nested right joins are bounded in total" {
  @expect.expect_all(soft => {
    for levels in [6, 12] {
      soft
      .expect_call(() => ev(nested_rights(levels)))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError",
      )
    }
    // A realistic nesting still runs.
    soft
    .expect(
      ev(
        "SELECT VALUE [a, b, c] FROM [1] AS a RIGHT JOIN ([2] AS b RIGHT JOIN [3] AS c ON TRUE) ON TRUE",
      ),
    )
    .to_equal(bag([List([Int(1), Int(2), Int(3)])]))
  })
}

///|
/// `levels` nested levels; each is `[1] AS a_d RIGHT JOIN (level d+1) ON TRUE`
/// followed by `r` more RIGHT JOINs.
fn nested_rights_each(levels : Int, r : Int) -> String {
  let mut text = "[1] AS z CROSS JOIN [1] AS y"
  for d = levels - 1; d >= 0; d = d - 1 {
    let mut level = "[1] AS a" +
      d.to_string() +
      " RIGHT JOIN (" +
      text +
      ") ON TRUE"
    for _ in 0..<r {
      level = level + " RIGHT JOIN [1] AS w" + d.to_string() + " ON TRUE"
    }
    text = level
  }
  "SELECT VALUE z FROM " + text
}

///|
test "right joins after a nested item count against it" {
  @expect.expect_all(soft => {
    for shape in [(20, 100), (10, 50)] {
      soft
      .expect_call(() => ev(nested_rights_each(shape.0, shape.1)))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError",
      )
    }
  })
}
