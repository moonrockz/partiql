///|
test "OUTER set operations" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("<<1, 2, 2, 3, 3, 3>> OUTER UNION <<1, 2, 3, 3>>"))
    .to_equal(bag_of([Int(1), Int(2), Int(3)]))
    soft
    .expect(ev("<<1, 2, 2>> OUTER UNION ALL <<1, 3>>"))
    .to_equal(bag_of([Int(1), Int(2), Int(2), Int(1), Int(3)]))
    soft
    .expect(ev("<<1, 2, 2, 3, 3, 3>> OUTER INTERSECT <<1, 2, 3, 3>>"))
    .to_equal(bag_of([Int(1), Int(2), Int(3)]))
    soft
    .expect(ev("<<1, 2, 2, 3, 3, 3>> OUTER INTERSECT ALL <<1, 2, 3, 3>>"))
    .to_equal(bag_of([Int(1), Int(2), Int(3), Int(3)]))
    soft
    .expect(ev("<<1, 1, 1, 2>> OUTER EXCEPT <<1>>"))
    .to_equal(bag_of([Int(2)]))
    soft
    .expect(ev("<<1, 1, 1, 2>> OUTER EXCEPT ALL <<1>>"))
    .to_equal(bag_of([Int(1), Int(1), Int(2)]))
    // grouping equality: 1 and 1.0 are one value
    soft.expect(ev("<<1>> OUTER INTERSECT <<1.0>>")).to_equal(bag_of([Int(1)]))
    // lists are collections; the result is a bag
    soft
    .expect(ev("[1, 1, 1] OUTER EXCEPT ALL [1, 2]"))
    .to_equal(bag_of([Int(1), Int(1)]))
    // a scalar operand: a one-element bag in permissive mode, a TypeError in strict mode
    soft.expect(ev("1 OUTER UNION 2")).to_equal(bag_of([Int(1), Int(2)]))
    soft
    .expect_call(() => ev("1 OUTER UNION 2", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    // NULL and MISSING operands are the empty bag in both modes (RFC 0007)
    soft
    .expect(ev("<<1>> OUTER UNION NULL", mode=Strict))
    .to_equal(bag_of([Int(1)]))
    soft
    .expect(ev("<<1>> OUTER INTERSECT MISSING", mode=Strict))
    .to_equal(bag_of([]))
    // a MISSING element is kept
    soft
    .expect(ev("<<1>> OUTER UNION <<MISSING>>"))
    .to_equal(bag_of([Int(1), Missing]))
  })
}

///|
/// Evaluates `source` with two small relations, `hr` and `eng`.
fn q(source : String, mode~ : @eval.Mode = Permissive) -> @value.Value raise {
  let env = @eval.Bindings::of_ion(
    @text.read_ion(
      "{hr: $bag::[{name: \"Bob\", title: \"C\"}, {name: \"Sue\", title: \"M\"}], eng: $bag::[{title: \"M\", name: \"Paul\"}]}",
    ),
  )
  @eval.evaluate_text(source, env~, mode~)
}

///|
test "SQL set operations" {
  @expect.expect_all(soft => {
    // positional: the right tuple takes the left names (RFC 0007 Example 2.1)
    soft
    .expect(q("SELECT * FROM hr UNION ALL SELECT * FROM eng"))
    .to_equal(
      bag_of([
        tuple([("name", String("Bob")), ("title", String("C"))]),
        tuple([("name", String("Sue")), ("title", String("M"))]),
        tuple([("name", String("M")), ("title", String("Paul"))]),
      ]),
    )
    // CORRESPONDING BY matches names (Example 2.2)
    soft
    .expect(
      q(
        "SELECT * FROM hr UNION ALL CORRESPONDING BY (name, title) SELECT * FROM eng",
      ),
    )
    .to_equal(
      bag_of([
        tuple([("name", String("Bob")), ("title", String("C"))]),
        tuple([("name", String("Sue")), ("title", String("M"))]),
        tuple([("name", String("Paul")), ("title", String("M"))]),
      ]),
    )
    // plain CORRESPONDING: the shared names in left order
    soft
    .expect(q("SELECT * FROM hr INTERSECT CORRESPONDING SELECT * FROM eng"))
    .to_equal(bag_of([]))
    soft
    .expect(q("SELECT title FROM hr INTERSECT SELECT title FROM eng"))
    .to_equal(bag_of([tuple([("title", String("M"))])]))
    soft
    .expect(q("SELECT title FROM hr EXCEPT SELECT title FROM eng"))
    .to_equal(bag_of([tuple([("title", String("C"))])]))
    // a different degree, a non-tuple element, a scalar operand, incompatible columns: DataError in both modes
    for
      s in [
        "SELECT * FROM hr UNION SELECT title FROM eng", "hr UNION <<MISSING>>", "1 UNION 2",
        "SELECT * FROM <<1>> UNION SELECT * FROM <<'A'>>",
      ] {
      soft
      .expect_call(() => q(s))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError: \{s}",
      )
      soft
      .expect_call(() => q(s, mode=Strict))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError: \{s}",
      )
    }
    // Review Focus 5: an empty side
    // CORRESPONDING with an empty side takes the columns of the other side
    let bob = tuple([("name", String("Bob")), ("title", String("C"))])
    let sue = tuple([("name", String("Sue")), ("title", String("M"))])
    let paul = tuple([("name", String("Paul")), ("title", String("M"))])
    soft
    .expect(
      q("SELECT * FROM hr UNION CORRESPONDING SELECT * FROM eng WHERE false"),
    )
    .to_equal(bag_of([bob, sue]))
    soft
    .expect(
      q("SELECT * FROM hr WHERE false UNION CORRESPONDING SELECT * FROM eng"),
    )
    .to_equal(bag_of([paul]))
    soft
    .expect(
      q(
        "SELECT * FROM hr OUTER UNION CORRESPONDING SELECT * FROM eng WHERE false",
      ),
    )
    .to_equal(bag_of([bob, sue]))
    soft
    .expect(
      q(
        "SELECT * FROM hr WHERE false OUTER UNION ALL CORRESPONDING SELECT * FROM eng",
      ),
    )
    .to_equal(bag_of([paul]))
    // SQL CORRESPONDING without a common column: DataError in both modes
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect_call(() => {
        q("SELECT * FROM hr UNION CORRESPONDING SELECT 1 AS z FROM eng", mode~)
      })
      .to_raise_matching(
        e => {
          e
          is @eval.EvalError::DataError(
            message="CORRESPONDING finds no common column",
            ..
          )
        },
        description="DataError: no common column",
      )
    }
    soft
    .expect(q("SELECT title FROM [] AS x UNION SELECT title FROM eng"))
    .to_equal(bag_of([tuple([("title", String("M"))])]))
    soft
    .expect(q("SELECT title FROM hr INTERSECT SELECT x.title FROM [] AS x"))
    .to_equal(bag_of([]))
    // ORDER BY and LIMIT over a set operation (setop.ion)
    soft
    .expect(
      q(
        "(SELECT title AS t FROM hr) UNION (SELECT title AS t FROM eng) ORDER BY t DESC LIMIT 1",
      ),
    )
    .to_equal(List([tuple([("t", String("M"))])]))
  })
}

///|
test "a long set-operation chain runs without overflowing the stack" {
  @expect.expect_all(soft => {
    soft
    .expect(ev("<<1>>" + " OUTER UNION <<1>>".repeat(9999)))
    .to_equal(bag_of([Int(1)]))
    soft
    .expect(ev("<<{'a': 1}>>" + " UNION <<{'a': 1}>>".repeat(9999)))
    .to_equal(bag_of([tuple([("a", Int(1))])]))
    soft
    .expect(ev("<<1>>" + " OUTER INTERSECT <<1>>".repeat(9999)))
    .to_equal(bag_of([Int(1)]))
  })
}

///|
test "a deeply nested set operation is an error, not a stack overflow" {
  let one = "SELECT VALUE x FROM <<1>> AS x"
  let nested = (n : Int32) => {
    "\{one} OUTER UNION (".repeat(n) + one + ")".repeat(n)
  }
  @expect.expect_all(soft => {
    soft.expect(ev(nested(30))).to_equal(bag_of([Int(1)]))
    soft
    .expect_call(() => ev(nested(1000)))
    .to_raise_matching(
      e => {
        e is @eval.EvalError::DataError(..) || e is @eval.EvalError::Syntax(_)
      },
      description="DataError or Syntax",
    )
  })
}
