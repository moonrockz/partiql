///|
test "absent values and arithmetic" {
  @expect.expect_all(soft => {
    soft.expect(ev("NULL + MISSING")).to_equal(Missing)
    soft.expect(ev("NULL + 1")).to_equal(Null)
    soft.expect(ev("MISSING = MISSING")).to_equal(Missing)
    // NULL wins in `=` (null.ion), MISSING wins in `||` (concat.ion).
    soft.expect(ev("MISSING = NULL")).to_equal(Null)
    soft.expect(ev("NULL || MISSING")).to_equal(Missing)
    soft.expect(ev("1 + 2 * 3")).to_equal(Int(7))
    soft.expect(ev("7 / 2")).to_equal(Int(3))
    soft.expect(ev("-7 / 2")).to_equal(Int(-3))
    soft.expect(ev("-7 % 2")).to_equal(Int(-1))
    soft.expect(ev("1 + 1.5")).to_equal(Decimal(@ion.Decimal::parse("2.5")))
    soft.expect(ev("1 + 1e0")).to_equal(Decimal(@ion.Decimal::parse("2")))
    soft.expect(ev("1 + 'a'")).to_equal(Missing)
    soft.expect(ev("1 + (2 || 3)")).to_equal(Missing)
    soft.expect(ev("(1 + 'a') IS MISSING")).to_equal(Bool(true))
    soft.expect(ev("'a' || 'b'")).to_equal(String("ab"))
  })
}

///|
test "strict mode raises; division by zero fails in both modes" {
  @expect.expect_all(soft => {
    soft
    .expect_call(() => ev("1 + 'a'", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
    soft.expect(ev("NULL + 1", mode=Strict)).to_equal(Null)
    for mode in [@eval.Mode::Permissive, Strict] {
      soft
      .expect_call(() => ev("1 / 0", mode~))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError",
      )
      soft
      .expect_call(() => ev("1.0 / 0", mode~))
      .to_raise_matching(
        e => e is @eval.EvalError::DataError(..),
        description="DataError",
      )
    }
  })
}

///|
test "comparison, logic and predicates" {
  @expect.expect_all(soft => {
    soft.expect(ev("1 < 2.5")).to_equal(Bool(true))
    soft.expect(ev("'a' < 'b'")).to_equal(Bool(true))
    soft.expect(ev("1 < 'a'")).to_equal(Missing)
    soft.expect(ev("1 = 1.0")).to_equal(Bool(true))
    soft.expect(ev("FALSE AND MISSING")).to_equal(Bool(false))
    // Logic does not tell MISSING from NULL (logical.ion).
    soft.expect(ev("TRUE AND MISSING")).to_equal(Null)
    soft.expect(ev("TRUE OR MISSING")).to_equal(Bool(true))
    soft.expect(ev("NULL OR FALSE")).to_equal(Null)
    soft.expect(ev("NOT MISSING")).to_equal(Null)
    soft.expect(ev("2 BETWEEN 1 AND 3")).to_equal(Bool(true))
    soft.expect(ev("2 IN [1, 2]")).to_equal(Bool(true))
    soft.expect(ev("3 IN [1, NULL]")).to_equal(Null)
    soft.expect(ev("3 IN (1, 2)")).to_equal(Bool(false))
    soft
    .expect(ev("CASE WHEN 1 = 2 THEN 'a' ELSE 'b' END"))
    .to_equal(String("b"))
    soft
    .expect(ev("CASE 2 WHEN 1 THEN 'a' WHEN 2 THEN 'b' END"))
    .to_equal(String("b"))
    soft.expect(ev("CASE WHEN FALSE THEN 1 END")).to_equal(Null)
    soft.expect(ev("COALESCE(NULL, MISSING, 3)")).to_equal(Int(3))
    soft.expect(ev("NULLIF(1, 1)")).to_equal(Null)
    soft.expect(ev("1 IS INT")).to_equal(Bool(true))
    soft.expect(ev("'a' IS STRING")).to_equal(Bool(true))
    soft.expect(ev("NULL IS INT")).to_equal(Bool(false))
    soft.expect(ev("TRUE IS TRUE")).to_equal(Bool(true))
    soft.expect(ev("NULL IS UNKNOWN")).to_equal(Bool(true))
  })
}

///|
/// The extended corpus (int.ion, `int_overflow_error`) fails an integer
/// literal and an integer result outside Int64 in both modes.
test "integer overflow is a data error in both modes" {
  @expect.expect_all(soft => {
    for mode in [@eval.Mode::Permissive, Strict] {
      for
        source in [
          "9223372036854775807 + 1", "-9223372036854775808 - 1", "9223372036854775807 * 2",
          "-9223372036854775808 / -1", "9223372036854775808", "-9223372036854775809",
          "99999999999999999999",
        ] {
        soft
        .expect_call(() => ev(source, mode~))
        .to_raise_matching(
          e => e is @eval.EvalError::DataError(..),
          description="DataError for \{source}",
        )
      }
    }
    soft.expect(ev("-9223372036854775808")).to_equal(Int(-9223372036854775808L))
    soft
    .expect(ev("9223372036854775807 + 0"))
    .to_equal(Int(9223372036854775807L))
  })
}

///|
test "decimal arithmetic, division and rounding" {
  let dec = (s : String) => @value.Value::Decimal(@ion.Decimal::parse(s))
  @expect.expect_all(soft => {
    soft.expect(ev("1.5 * 2")).to_equal(dec("3.0"))
    soft.expect(ev("1.5 - 0.25")).to_equal(dec("1.25"))
    soft.expect(ev("1.0 / 4")).to_equal(dec("0.25"))
    soft.expect(ev("6.0 / 3")).to_equal(dec("2.0"))
    soft
    .expect(ev("1.0 / 3"))
    .to_equal(dec("0.33333333333333333333333333333333333333"))
    soft
    .expect(ev("2.0 / 3"))
    .to_equal(dec("0.66666666666666666666666666666666666667"))
    soft
    .expect(ev("4.0000 / 3.0"))
    .to_equal(dec("1.3333333333333333333333333333333333333"))
    soft.expect(ev("7.5 % 2")).to_equal(dec("1.5"))
    soft.expect(ev("-7.5 % 2")).to_equal(dec("-1.5"))
    // A number with an exponent is a decimal; a float sets in by Ion only.
    soft.expect(ev("1e0 / 4")).to_equal(dec("0.25"))
    soft.expect(ev("1.5 + 1e0")).to_equal(dec("2.5"))
    soft
    .expect(ev("1e100 - 1e-100"))
    .to_equal(dec("10000000000000000000000000000000000000d63"))
    soft
    .expect(ev("9223372036854775807.0 + 100.0"))
    .to_equal(dec("9223372036854775907.0"))
    // A long decimal literal rounds half even to 38 digits, also when negative.
    soft
    .expect(ev("-0.123456789012345678901234567890123456785"))
    .to_equal(dec("-0.12345678901234567890123456789012345678"))
    soft
    .expect(ev("-0.123456789012345678901234567890123456786"))
    .to_equal(dec("-0.12345678901234567890123456789012345679"))
  })
}

///|
test "unary operators, concatenation and comparison types" {
  @expect.expect_all(soft => {
    soft.expect(ev("-(1 + 2)")).to_equal(Int(-3))
    soft.expect(ev("+5")).to_equal(Int(5))
    soft.expect(ev("-NULL")).to_equal(Null)
    soft.expect(ev("-MISSING")).to_equal(Missing)
    soft.expect(ev("-'a'")).to_equal(Missing)
    soft.expect(ev("'a' || NULL")).to_equal(Null)
    soft.expect(ev("'a' || MISSING")).to_equal(Missing)
    soft.expect(ev("TRUE > FALSE")).to_equal(Bool(true))
    soft.expect(ev("1 <> 2")).to_equal(Bool(true))
    soft.expect(ev("1 <> MISSING")).to_equal(Missing)
    soft.expect(ev("2 NOT BETWEEN 1 AND 3")).to_equal(Bool(false))
    soft.expect(ev("3 NOT IN [1, 2]")).to_equal(Bool(true))
    soft.expect(ev("NULL IS NOT UNKNOWN")).to_equal(Bool(false))
    soft.expect(ev("1 IS NOT TRUE")).to_equal(Bool(true))
    soft.expect(ev("[1] IS LIST")).to_equal(Bool(true))
    soft.expect(ev("MISSING IS MISSING")).to_equal(Bool(true))
  })
}

///|
test "a float from Ion: float with int is float, float with decimal is decimal" {
  let env = @eval.Bindings::of_tuple(
    @value.Tuple::new([
      ("f", Float(2.0)),
      ("d", Decimal(@ion.Decimal::parse("3."))),
      ("i", Int(1)),
    ]),
  )
  let run = (source : String) => @eval.evaluate_text(source, env~)
  @expect.expect_all(soft => {
    soft.expect(run("i + f")).to_equal(Float(3.0))
    soft.expect(run("-f")).to_equal(Float(-2.0))
    soft.expect(run("f * 2 * 4")).to_equal(Float(16.0))
    soft.expect(run("i - f - d")).to_equal(Decimal(@ion.Decimal::parse("-4.")))
    soft.expect(run("f < d")).to_equal(Bool(true))
  })
}

///|
test "IS DECIMAL(p, s) and IS MAP" {
  @expect.expect_all(soft => {
    soft.expect(ev("1.0000 IS DECIMAL(5,3)")).to_equal(Bool(false))
    soft.expect(ev("0.001 IS DECIMAL(3,3)")).to_equal(Bool(true))
    soft.expect(ev("123.456 IS DECIMAL(5,3)")).to_equal(Bool(false))
    soft.expect(ev("0123.456 IS DECIMAL(6,3)")).to_equal(Bool(true))
    soft.expect(ev("0.00 IS DECIMAL(4,3)")).to_equal(Bool(true))
    soft.expect(ev("1.5 IS NOT DECIMAL")).to_equal(Bool(false))
    soft.expect(ev("NULL IS MAP<STRING, INTEGER>")).to_equal(Null)
    soft.expect(ev("MISSING IS MAP<STRING, INTEGER>")).to_equal(Missing)
    soft.expect(ev("2147483648 IS INT")).to_equal(Bool(false))
    soft.expect(ev("2147483648 IS BIGINT")).to_equal(Bool(true))
  })
}

///|
test "a non-boolean under NOT is a type error in strict mode" {
  @expect.expect_all(soft => {
    soft.expect(ev("NOT {'a': 1}")).to_equal(Missing)
    soft
    .expect_call(() => ev("NOT {'a': 1}", mode=Strict))
    .to_raise_matching(
      e => e is @eval.EvalError::TypeError(..),
      description="TypeError",
    )
  })
}
