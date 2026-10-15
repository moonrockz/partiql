///|
test "length functions" {
  @expect.expect_all(soft => {
    soft.expect(ev("CHAR_LENGTH('abc')")).to_equal(Int(3))
    soft.expect(ev("character_length('😁x')")).to_equal(Int(2))
    soft.expect(ev("Char_Length('')")).to_equal(Int(0))
    soft.expect(ev("OCTET_LENGTH('français')")).to_equal(Int(9))
    soft.expect(ev("bit_length('abc')")).to_equal(Int(24))
    soft.expect(ev("char_length(`abc`)")).to_equal(Int(3))
    soft.expect(ev("char_length(`\"ab\"`)")).to_equal(Int(2))
  })
}

///|
test "absent and wrong-type arguments in both modes" {
  @expect.expect_all(soft => {
    soft.expect(ev("char_length(NULL)")).to_equal(Null)
    soft.expect(ev("char_length(NULL)", mode=Strict)).to_equal(Null)
    soft.expect(ev("char_length(MISSING)")).to_equal(Missing)
    soft.expect(ev("char_length(MISSING)", mode=Strict)).to_equal(Missing)
    soft.expect(ev("char_length(1)")).to_equal(Missing)
    soft
    .expect_call(() => ev("char_length(1)", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}

///|
test "name resolution and static checks" {
  @expect.expect_all(soft => {
    // An unknown name is not supported yet. The parser rejects a delimited
    // function name, so it never reaches the built-ins.
    soft
    .expect_call(() => ev("no_such_function('a')"))
    .to_raise_matching(
      e => e is @eval.EvalError::Unsupported(..),
      description="Unsupported",
    )
    soft
    .expect_call(() => ev("\"char_length\"('a')"))
    .to_raise_matching(
      e => e is @eval.EvalError::Syntax(_),
      description="Syntax",
    )
    // Wrong arity, a set quantifier and `*` are static errors in both modes.
    for
      source in [
        "char_length('a', 'b')", "char_length()", "char_length(DISTINCT 'a')", "char_length(ALL 'a')",
        "char_length(*)",
      ] {
      for mode in [@eval.Mode::Permissive, Strict] {
        soft
        .expect_call(() => ev(source, mode~))
        .to_raise_matching(
          e => e is @eval.EvalError::DataError(..),
          description="DataError for \{source}",
        )
      }
    }
  })
}

///|
test "a function as a GROUP BY key and around an aggregate" {
  let rows = "<<{'a': 'xy'}, {'a': 'zw'}, {'a': 'q'}>>"
  @expect.expect_all(soft => {
    soft
    .expect(
      ev(
        "SELECT CHAR_LENGTH(t.a) AS n, COUNT(*) AS c FROM \{rows} AS t GROUP BY CHAR_LENGTH(t.a)",
      ),
    )
    .to_equal(
      bag_of([
        tuple([("n", Int(2)), ("c", Int(2))]),
        tuple([("n", Int(1)), ("c", Int(1))]),
      ]),
    )
    soft
    .expect(ev("SELECT VALUE CHAR_LENGTH(MAX(t.a)) FROM \{rows} AS t"))
    .to_equal(bag_of([Int(2)]))
  })
}
