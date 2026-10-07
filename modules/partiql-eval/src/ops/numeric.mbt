///|
/// A number, by its kind: arithmetic widens integer to decimal to float.
priv enum Num {
  Whole(@bigint.BigInt)
  Exact(@ion_core.Decimal)
  Approx(Double)
}

///|
fn number(v : @value.Value) -> Num? {
  match v {
    Int(n) => Some(Whole(@bigint.BigInt::from_int64(n)))
    BigInt(n) => Some(Whole(n))
    Decimal(d) => Some(Exact(d))
    Float(f) => Some(Approx(f))
    _ => None
  }
}

///|
fn whole_to_double(n : @bigint.BigInt) -> Double raise OpFailure {
  try @string.parse_double(n.to_string()) catch {
    _ => raise DataFailure("an integer out of the float range")
  } noraise {
    d => d
  }
}

///|
fn to_double(n : Num) -> Double raise OpFailure {
  match n {
    Whole(w) => whole_to_double(w)
    Exact(d) =>
      match d.to_double() {
        Some(x) => x
        None => raise DataFailure("a decimal out of the float range")
      }
    Approx(f) => f
  }
}

///|
/// A float becomes the decimal of its shortest text. NaN and the infinities
/// have none.
fn to_decimal(n : Num) -> @ion_core.Decimal raise OpFailure {
  match n {
    Whole(w) => @ion_core.Decimal::new(w, 0)
    Exact(d) => d
    Approx(f) =>
      if f.is_nan() || f.is_inf() {
        raise DataFailure("NaN or infinity in decimal arithmetic")
      } else {
        match parse_decimal(f.to_string()) {
          Some(d) => d
          None => raise DataFailure("a float without a decimal")
        }
      }
  }
}

///|
/// An integer result: `Int` when it fits in Int64. A larger result is an
/// error (partiql-tests extended int.ion, `int_overflow_error`).
fn whole_value(n : @bigint.BigInt) -> @value.Value raise OpFailure {
  if n.compare_int64(9223372036854775807L) <= 0 &&
    n.compare_int64(-9223372036854775808L) >= 0 {
    Int(n.to_int64())
  } else {
    raise DataFailure("integer overflow")
  }
}

///|
/// The absent-value rules, then the number kinds. `whole`, `exact` and
/// `approx` compute on two integers, two decimals and two floats. An integer
/// widens to a float, and a float or an integer widens to a decimal when the
/// other operand is a decimal (partiql-tests nary-operators.ion,
/// `subIntFloatDecimal`).
fn arithmetic(
  a : @value.Value,
  b : @value.Value,
  whole~ : (@bigint.BigInt, @bigint.BigInt) -> @value.Value raise OpFailure,
  exact~ : (@ion_core.Decimal, @ion_core.Decimal) -> @ion_core.Decimal raise OpFailure,
  approx~ : (Double, Double) -> Double raise OpFailure,
) -> @value.Value raise OpFailure {
  let x = boxed(a)
  let y = boxed(b)
  if x is Missing || y is Missing {
    return Missing
  }
  if x is Null || y is Null {
    return Null
  }
  match (number(x), number(y)) {
    (Some(Whole(m)), Some(Whole(n))) => whole(m, n)
    (Some(p), Some(q)) =>
      if p is Exact(_) || q is Exact(_) {
        Decimal(exact(to_decimal(p), to_decimal(q)))
      } else {
        Float(approx(to_double(p), to_double(q)))
      }
    _ => raise TypeFailure("arithmetic on a value that is not a number")
  }
}

///|
pub fn add(a : @value.Value, b : @value.Value) -> @value.Value raise OpFailure {
  arithmetic(a, b, whole=(m, n) => whole_value(m + n), exact=decimal_add, approx=(
    p,
    q,
  ) => p + q)
}

///|
pub fn sub(a : @value.Value, b : @value.Value) -> @value.Value raise OpFailure {
  arithmetic(a, b, whole=(m, n) => whole_value(m - n), exact=decimal_sub, approx=(
    p,
    q,
  ) => p - q)
}

///|
pub fn mul(a : @value.Value, b : @value.Value) -> @value.Value raise OpFailure {
  arithmetic(
    a,
    b,
    whole=(m, n) => whole_value(m * n),
    exact=(p, q) => decimal_mul(p, q),
    approx=(p, q) => p * q,
  )
}

///|
/// Integer division truncates toward zero; a zero divisor of an integer or
/// decimal is a `DataFailure`, a float divides as IEEE does.
pub fn div(a : @value.Value, b : @value.Value) -> @value.Value raise OpFailure {
  arithmetic(
    a,
    b,
    whole=(m, n) => {
      if n.is_zero() {
        raise DataFailure("division by zero")
      } else {
        whole_value(m / n)
      }
    },
    exact=decimal_div,
    approx=(p, q) => p / q,
  )
}

///|
/// The remainder has the sign of the dividend.
pub fn rem(a : @value.Value, b : @value.Value) -> @value.Value raise OpFailure {
  arithmetic(
    a,
    b,
    whole=(m, n) => {
      if n.is_zero() {
        raise DataFailure("division by zero")
      } else {
        whole_value(m % n)
      }
    },
    exact=decimal_rem,
    approx=(p, q) => p % q,
  )
}

///|
/// `-x`, and `+x` when `negate` is false.
pub fn neg(v : @value.Value, negate~ : Bool) -> @value.Value raise OpFailure {
  let x = boxed(v)
  match x {
    Null | Missing => x
    _ =>
      match number(x) {
        None => raise TypeFailure("a sign on a value that is not a number")
        Some(_) if !negate => x
        Some(Whole(n)) => whole_value(-n)
        Some(Exact(d)) =>
          Decimal(@ion_core.Decimal::new(-d.coefficient(), d.exponent()))
        Some(Approx(f)) => Float(-f)
      }
  }
}

///|
/// `a || b`: the concatenation of two strings.
pub fn concat(
  a : @value.Value,
  b : @value.Value,
) -> @value.Value raise OpFailure {
  let x = boxed(a)
  let y = boxed(b)
  match (x, y) {
    (Missing, _) | (_, Missing) => Missing
    (Null, _) | (_, Null) => Null
    (String(p), String(q)) => String(p + q)
    _ => raise TypeFailure("|| on a value that is not a string")
  }
}
