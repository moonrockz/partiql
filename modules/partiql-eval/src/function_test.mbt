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

///|
test "collection functions; a subquery argument stays a collection" {
  @expect.expect_all(soft => {
    soft.expect(ev("SIZE([1, 2, 3])")).to_equal(Int(3))
    soft.expect(ev("cardinality(<<1, NULL>>)")).to_equal(Int(2))
    soft.expect(ev("size({'a': 1, 'a': 2})")).to_equal(Int(2))
    soft.expect(ev("size(`(1 2)`)")).to_equal(Int(2))
    soft
    .expect(ev("size(SELECT a FROM <<{'a': 1}, {'a': 2}>>)"))
    .to_equal(Int(2))
    soft
    .expect(ev("cardinality(SELECT a FROM <<{'a': 1}, {'a': 2}>>)"))
    .to_equal(Int(2))
    soft.expect(ev("exists(select * from [1])")).to_equal(Bool(true))
    soft.expect(ev("EXISTS([])")).to_equal(Bool(false))
    soft
    .expect(ev("TUPLEUNION({'a': 1}, {'b': 2})"))
    .to_equal(tuple([("a", Int(1)), ("b", Int(2))]))
    soft.expect(ev("tupleunion()")).to_equal(tuple([]))
    soft.expect(ev("cardinality('foo')")).to_equal(Missing)
  })
}

///|
test "map functions and m[k] share the key rule" {
  @expect.expect_all(soft => {
    soft.expect(ev("MAP { 1.0: 'one', 2.0: 'two' }[1]")).to_equal(String("one"))
    soft
    .expect(ev("map_get(MAP { 1.0: 'one', 2.0: 'two' }, 1)"))
    .to_equal(String("one"))
    soft.expect(ev("map_get(MAP { 'a': 1 }, 'z')")).to_equal(Missing)
    soft
    .expect_call(() => ev("map_get(MAP { 'a': 1 }, 'z')", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    soft
    .expect_call(() => ev("MAP { 1: 'one' }['1']", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    soft
    .expect(ev("map_contains_key(MAP { 1: 'one' }, 1)"))
    .to_equal(Bool(true))
    soft
    .expect(ev("MAP_KEYS(MAP { 'x': 1, 'y': 2 })"))
    .to_equal(bag_of([String("x"), String("y")]))
    soft
    .expect(ev("map_entries(MAP { 'a': 1 })"))
    .to_equal(bag_of([tuple([("k", String("a")), ("v", Int(1))])]))
  })
}

///|
test "ABS and MOD end to end; deep nesting is a static error" {
  let deep = "ABS(".repeat(1000) + "-1" + ")".repeat(1000)
  @expect.expect_all(soft => {
    soft.expect(ev("ABS(-3)")).to_equal(Int(3))
    soft.expect(ev("abs(1.0)")).to_equal(dec("1.0"))
    soft.expect(ev("MOD(-17, 4)")).to_equal(Int(-1))
    soft.expect(ev("MOD(MISSING, 'some string')")).to_equal(Missing)
    soft
    .expect_call(() => ev("MOD(NULL, 'some string')", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect_call(() => ev("MOD(1, 0)", mode~))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError",
      )
      // The parser or the lowering stops it: an error, never a stack overflow.
      soft
      .expect_call(() => ev(deep, mode~))
      .to_raise_matching(
        e => e is (@eval.EvalError::Syntax(_) | @eval.EvalError::DataError(..)),
        description="Syntax or DataError: too deep",
      )
    }
  })
}

///|
test "special forms equal their comma forms" {
  @expect.expect_all(soft => {
    soft.expect(ev("TRIM('  a  ')")).to_equal(String("a"))
    soft.expect(ev("trim(both '12' from '121a21')")).to_equal(String("a"))
    soft.expect(ev("trim(leading from '  a  ')")).to_equal(String("a  "))
    soft.expect(ev("trim(trailing 'x' from 'xax')")).to_equal(String("xa"))
    soft.expect(ev("trim('x' from 'xax')")).to_equal(String("a"))
    soft.expect(ev("SUBSTRING('abcdef' FROM 2 FOR 3)")).to_equal(String("bcd"))
    soft.expect(ev("substring('abcdef', 2, 3)")).to_equal(String("bcd"))
    soft.expect(ev("substring('abcdef' FROM 3)")).to_equal(String("cdef"))
    soft.expect(ev("POSITION('c' IN 'abc')")).to_equal(Int(3))
    soft.expect(ev("position('c', 'abc')")).to_equal(Int(3))
    soft
    .expect(ev("OVERLAY('hello' PLACING 'XX' FROM 2 FOR 3)"))
    .to_equal(String("hXXo"))
    soft.expect(ev("overlay('hello', 'XX', 2, 3)")).to_equal(String("hXXo"))
    soft.expect(ev("text_replace('aXa', 'X', 'b')")).to_equal(String("aba"))
    soft.expect(ev("substring('1', 4, -11)")).to_equal(Missing)
    soft
    .expect_call(() => ev("substring('1', 4, -11)", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}

///|
test "UPPER and LOWER end to end; a symbol gives a string" {
  @expect.expect_all(soft => {
    soft.expect(ev("UPPER('straße')")).to_equal(String("STRASSE"))
    soft.expect(ev("lower('ΣΑΣ')")).to_equal(String("σας"))
    soft.expect(ev("upper(`abc`)")).to_equal(String("ABC"))
    soft.expect(ev("upper(1)")).to_equal(Missing)
  })
}
