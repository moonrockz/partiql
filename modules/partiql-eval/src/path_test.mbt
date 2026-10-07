///|
fn ev_env(
  source : String,
  env : String,
  mode? : @eval.Mode = Permissive,
) -> @value.Value raise {
  @eval.evaluate_text(
    source,
    env=@eval.Bindings::of_ion(@text.read_ion(env)),
    mode~,
  )
}

///|
test "variables and paths" {
  @expect.expect_all(soft => {
    soft.expect(ev_env("a.b", "{a: {b: 1}}")).to_equal(Int(1))
    soft.expect(ev_env("A.B", "{a: {b: 1}}")).to_equal(Int(1))
    soft.expect(ev_env("\"a\".b", "{a: {b: 1}}")).to_equal(Int(1))
    soft.expect(ev_env("{'Foo': 1}.foo", "{}")).to_equal(Int(1))
    soft.expect(ev_env("{'Foo': 1}.\"foo\"", "{}")).to_equal(Missing)
    soft.expect(ev_env("{'a': 1}['a']", "{}")).to_equal(Int(1))
    soft.expect(ev_env("[10, 20][1]", "{}")).to_equal(Int(20))
    soft.expect(ev_env("[10, 20][5]", "{}")).to_equal(Missing)
    soft.expect(ev_env("<<1, 2, 3>>[1]", "{}")).to_equal(Missing)
    soft.expect(ev_env("'not a tuple'.a", "{}")).to_equal(Missing)
    soft.expect(ev_env("a.z.y.x", "{a: {}}")).to_equal(Missing)
    soft
    .expect(ev_env("[1, 2][*]", "{}"))
    .to_equal(Bag(@value.Bag::new([Int(1), Int(2)])))
    soft
    .expect(ev_env("{'a': 1, 'b': 2}.*", "{}"))
    .to_equal(Bag(@value.Bag::new([Int(1), Int(2)])))
    soft.expect(ev_env("a.z IS MISSING", "{a: {}}")).to_equal(Bool(true))
    soft.expect(ev_env("a IS NOT MISSING", "{a: 1}")).to_equal(Bool(true))
    soft.expect(ev_env("NULL IS NULL", "{}")).to_equal(Bool(true))
    soft.expect(ev_env("MISSING IS NULL", "{}")).to_equal(Bool(true))
    soft.expect(ev_env("NULL IS MISSING", "{}")).to_equal(Bool(false))
    soft.expect(ev_env("1 IS NOT NULL", "{}")).to_equal(Bool(true))
    soft.expect(ev_env("MAP {'a': 1}['a']", "{}")).to_equal(Int(1))
    soft.expect(ev_env("MAP {'a': 1}[NULL]", "{}")).to_equal(Null)
    soft.expect(ev_env("MAP {'a': 1}[MISSING]", "{}")).to_equal(Missing)
    soft.expect(ev_env("MAP {'a': 1}['z']", "{}")).to_equal(Missing)
  })
}

///|
test "strict mode: a failed path step is an error" {
  @expect.expect_all(soft => {
    for
      source in [
        "{'a': 1}.noSuchAttribute", "a.z IS MISSING", "(MISSING).a", "<<1, 2, 3>>[1]",
        "MAP {'a': 1}['z']", "'x'.a",
      ] {
      soft
      .expect_call(() => ev_env(source, "{a: {}}", mode=Strict), label=source)
      .to_raise_matching(
        e => e is @eval.EvalError::TypeError(..),
        description="TypeError",
      )
    }
  })
}

///|
test "an undefined variable is an error in both modes" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for source in ["nope", "nope IS MISSING", "\"A\""] {
        soft
        .expect_call(() => ev_env(source, "{a: 1}", mode~), label=source)
        .to_raise_matching(
          e => e is @eval.EvalError::TypeError(..),
          description="TypeError",
        )
      }
    }
  })
}

///|
test "map literals infer their types and follow the key rules" {
  @expect.expect_all(soft => {
    soft
    .expect(ev_env("MAP {'a': 1, 'a': 2}", "{}"))
    .to_equal(
      Map(
        @value.MapValue::new(key_type=String, value_type=Integer, [
          (String("a"), Int(2)),
        ]),
      ),
    )
    soft
    .expect(ev_env("MAP { }", "{}"))
    .to_equal(
      Map(@value.MapValue::new(key_type=String, value_type=Dynamic, [])),
    )
    soft
    .expect(ev_env("MAP {NULL: 1, 'b': 2}", "{}"))
    .to_equal(
      Map(
        @value.MapValue::new(key_type=String, value_type=Integer, [
          (String("b"), Int(2)),
        ]),
      ),
    )
    soft.expect(ev_env("MAP {NULL: 1}", "{}", mode=Strict)).to_equal(Null)
    soft
    .expect_call(() => ev_env("MAP {'a': 1, 'a': 2}", "{}", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}

///|
test "wildcards map later steps over the elements" {
  let env = "{s: 'hello', t: {n: 1}, l: [{a: 1}, {b: 2}, {a: 3}], k: 'a'}"
  let bag = (items : Array[@value.Value]) => {
    @value.Value::Bag(@value.Bag::new(items))
  }
  @expect.expect_all(soft => {
    soft.expect(ev_env("l[*].a", env)).to_equal(bag([Int(1), Int(3)]))
    soft.expect(ev_env("s[*]", env)).to_equal(bag([String("hello")]))
    soft.expect(ev_env("(100).*.*", env)).to_equal(bag([Int(100)]))
    soft.expect(ev_env("{}.*.*.bar", env)).to_equal(bag([]))
    soft.expect(ev_env("t.*.*", env)).to_equal(bag([Int(1)]))
    soft
    .expect(ev_env("(NULL).a IS MISSING", env, mode=Strict))
    .to_equal(Bool(true))
    soft.expect(ev_env("`null.int` IS NULL", env)).to_equal(Bool(true))
    soft.expect(ev_env("t[k]", env)).to_equal(Missing)
    soft.expect(ev_env("t['n']", env)).to_equal(Int(1))
    soft
    .expect_call(() => ev_env("s[*]", env, mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    soft
    .expect_call(() => ev_env("t[k]", env, mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}

///|
test "a decimal literal keeps 38 digits" {
  @expect.expect_all(soft => {
    soft
    .expect(ev_env("1.9999999999999999999999999999999999999999999999", "{}"))
    .to_equal(
      Decimal(@ion.Decimal::parse("2.0000000000000000000000000000000000000")),
    )
    soft
    .expect(ev_env("1.00000000000000000000000000000000000000000001", "{}"))
    .to_equal(
      Decimal(@ion.Decimal::parse("1.0000000000000000000000000000000000000")),
    )
  })
}
