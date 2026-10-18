///|
test "a session evaluates datagram elements in order without changing its bindings" {
  let session = @eval.Session::new(
    env=@eval.Bindings::of_pairs([("t", @value.Value::Int(99))]),
  )
  let values = @partiql_ion.read_text("{a: 3} {a: 1} {a: 2}")
  @expect.expect_all(soft => {
    soft
    .expect(session.evaluate_each("t.a", name="t", values~))
    .to_equal([@value.Value::Int(3), Int(1), Int(2)])
    soft.expect(session.evaluate_each("t", name="t", values=[])).to_equal([])
    soft.expect(session.evaluate("t")).to_equal(@value.Value::Int(99))
    let encoded = @partiql_ion.read_text("$bag::[1] $missing::null 3")
    soft
    .expect(session.evaluate_each("t", name="t", values=encoded))
    .to_equal(encoded)
  })
}

///|
test "sessions share mode, zone and clock across statements and survive failures" {
  let session = @eval.Session::new(
    mode=Strict,
    env=@eval.Bindings::of_pairs([("a", @value.Value::Int(2))]),
  )
  @expect.expect_all(soft => {
    soft
    .expect(session.evaluate_script("a; a + 1;"))
    .to_equal([@value.Value::Int(2), Int(3)])
    soft
    .expect_call(() => session.evaluate("1 + 'x'"))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="strict mode",
    )
    soft.expect(session.evaluate("a")).to_equal(@value.Value::Int(2))
    soft
    .expect(@partiql_ion.read_bytes(session.evaluate_ion_bytes("a; a + 1")))
    .to_equal([@value.Value::Int(2), Int(3)])
    soft
    .expect(@partiql_ion.read_text(session.evaluate_ion_text("a; a + 1")))
    .to_equal([@value.Value::Int(2), Int(3)])
  })
}

///|
test "session statements share the injected clock and zone" {
  let clock = @eval.Clock::fixed(@time.date_time(2026, 10, 16, hour=23))
  let zone = @eval.ZoneOffset::new(120).unwrap()
  let session = @eval.Session::new(clock~, zone~)
  let tomorrow = @value.Value::Date(
    @value.Date::new(year=2026, month=10, day=17),
  )
  @expect.expect(session.evaluate_script("CURRENT_DATE; CURRENT_DATE")).to_equal([
      tomorrow, tomorrow,
    ],
  )
}
