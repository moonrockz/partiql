///|
fn ev(
  source : String,
  mode~ : @eval.Mode = Permissive,
) -> @value.Value raise @eval.EvalError {
  @eval.evaluate_text(source, env=@eval.Bindings::empty(), mode~)
}

///|
test "literals and collections" {
  @expect.expect_all(soft => {
    soft.expect(ev("1")).to_equal(Int(1))
    soft.expect(ev("NULL")).to_equal(Null)
    soft.expect(ev("MISSING")).to_equal(Missing)
    soft.expect(ev("'abc'")).to_equal(String("abc"))
    soft.expect(ev("TRUE")).to_equal(Bool(true))
    soft.expect(ev("1.5")).to_equal(Decimal(@ion.Decimal::parse("1.5")))
    soft.expect(ev("1e0")).to_equal(Decimal(@ion.Decimal::parse("1")))
    soft.expect(ev("[1, 'a']")).to_equal(List([Int(1), String("a")]))
    soft.expect(ev("<<1, 2>>")).to_equal(Bag(@value.Bag::Bag([Int(1), Int(2)])))
    soft
    .expect(ev("{'a': 1, 'b': MISSING}"))
    .to_equal(@value.Value::from_tuple(@value.Tuple([("a", Int(1))])))
  })
}

///|
test "unsupported forms say so" {
  @expect.expect_all(soft => {
    soft
    .expect_call(() => ev("SELECT 1"))
    .to_raise_matching(
      e => e is @eval.EvalError::Unsupported(..),
      description="Unsupported",
    )
    soft
    .expect_call(() => ev("no_such_function('a')"))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    soft
    .expect_call(() => ev("SELECT FROM"))
    .to_raise_matching(
      e => e is @eval.EvalError::Syntax(_),
      description="Syntax",
    )
  })
}

///|
test "bindings and struct keys" {
  let env = @eval.Bindings::of_tuple(@value.Tuple::Tuple([("Foo", Int(7))]))
  @expect.expect_all(soft => {
    soft.expect(@eval.evaluate_text("foo", env~)).to_equal(Int(7))
    soft
    .expect_call(() => @eval.evaluate_text("\"foo\"", env~))
    .to_raise_matching(
      e => e is @eval.EvalError::DataError(..),
      description="DataError",
    )
    soft
    .expect(ev("{1: 2, 'a': 3}"))
    .to_equal(@value.Value::from_tuple(@value.Tuple([("a", Int(3))])))
    soft
    .expect_call(() => ev("{1: 2}", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}

///|
test "sexp and row literals are lists" {
  @expect.expect_all(soft => {
    soft.expect(ev("SEXP(1, 2)")).to_equal(List([Int(1), Int(2)]))
    soft.expect(ev("(1, 2)")).to_equal(List([Int(1), Int(2)]))
    soft.expect(ev("ROW(1, 2)")).to_equal(List([Int(1), Int(2)]))
  })
}

///|
test "Bindings::of_pairs keeps a MISSING global bound" {
  let env = @eval.Bindings::of_pairs([("t", Missing), ("u", Int(1))])
  @expect.expect_all(soft => {
    soft.expect(@eval.evaluate_text("t", env~)).to_equal(Missing)
    soft.expect(@eval.evaluate_text("t IS MISSING", env~)).to_equal(Bool(true))
    soft.expect(@eval.evaluate_text("u", env~)).to_equal(Int(1))
  })
}
