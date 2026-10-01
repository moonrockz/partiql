///|
/// An exact number: coefficient × 10^exponent, or a special double.
priv enum Num {
  NaN
  NegInf
  PosInf
  Finite(@bigint.BigInt, Int)
}

///|
fn finite(coefficient : @bigint.BigInt, exponent : Int) -> Num {
  if coefficient.is_zero() {
    Finite(0N, 0)
  } else {
    Finite(coefficient, exponent)
  }
}

///|
fn num_of_int64(n : Int64) -> Num {
  finite(@bigint.BigInt::from_int64(n), 0)
}

///|
fn num_of_bigint(n : @bigint.BigInt) -> Num {
  finite(n, 0)
}

///|
fn num_of_decimal(d : @ion_core.Decimal) -> Num {
  finite(d.coefficient, d.exponent)
}

///|
/// The exact value of a double: m × 2^e, written as a decimal.
fn num_of_double(d : Double) -> Num {
  if d.is_nan() {
    return NaN
  }
  if d.is_pos_inf() {
    return PosInf
  }
  if d.is_neg_inf() {
    return NegInf
  }
  let bits = d.reinterpret_as_uint64()
  let negative = bits >> 63 == 1UL
  let exponent_bits = ((bits >> 52) & 0x7FFUL).to_int()
  let fraction = bits & 0xFFFFFFFFFFFFFUL
  let (mantissa, e) = if exponent_bits == 0 {
    (fraction, -1074)
  } else {
    (fraction | 0x10000000000000UL, exponent_bits - 1075)
  }
  let m = @bigint.BigInt::from_uint64(mantissa)
  let (coefficient, exponent) = if e >= 0 {
    (m * 2N.pow(@bigint.BigInt::from_int(e)), 0)
  } else {
    (m * 5N.pow(@bigint.BigInt::from_int(-e)), e)
  }
  finite(if negative { -coefficient } else { coefficient }, exponent)
}

///|
/// -1, 0 or 1. `compare` results are only negative, zero or positive (on
/// wasm-gc, `BigInt::compare` returns other magnitudes), so normalize them.
fn unit(c : Int) -> Int {
  if c < 0 {
    -1
  } else if c > 0 {
    1
  } else {
    0
  }
}

///|
fn sign_of(n : @bigint.BigInt) -> Int {
  unit(n.compare(0N))
}

///|
fn digit_count(n : @bigint.BigInt) -> Int {
  let text = n.to_string()
  if text.has_prefix("-") {
    text.length() - 1
  } else {
    text.length()
  }
}

///|
/// Compares two finite decimals without scaling by more than their digit
/// counts.
fn compare_finite(
  c1 : @bigint.BigInt,
  e1 : Int,
  c2 : @bigint.BigInt,
  e2 : Int,
) -> Int {
  let s1 = sign_of(c1)
  let s2 = sign_of(c2)
  if s1 != s2 {
    return if s1 < s2 { -1 } else { 1 }
  }
  if s1 == 0 {
    return 0
  }
  // Same sign, both non-zero. Compare magnitudes, then apply the sign.
  let a1 = e1 + digit_count(c1)
  let a2 = e2 + digit_count(c2)
  let magnitude = if a1 != a2 {
    if a1 < a2 {
      -1
    } else {
      1
    }
  } else {
    // Equal adjusted exponents: the exponent gap is at most the digit gap.
    let (m1, m2) = if e1 >= e2 {
      (c1 * 10N.pow(@bigint.BigInt::from_int(e1 - e2)), c2)
    } else {
      (c1, c2 * 10N.pow(@bigint.BigInt::from_int(e2 - e1)))
    }
    let abs1 = if s1 < 0 { -m1 } else { m1 }
    let abs2 = if s1 < 0 { -m2 } else { m2 }
    unit(abs1.compare(abs2))
  }
  if s1 < 0 {
    -magnitude
  } else {
    magnitude
  }
}

///|
fn rank_of_num(n : Num) -> Int {
  match n {
    NaN => 0
    NegInf => 1
    Finite(_, _) => 2
    PosInf => 3
  }
}

///|
/// A total order: NaN < -inf < finite < +inf. NaN equals NaN; -0 equals 0.
fn compare_num(a : Num, b : Num) -> Int {
  match (a, b) {
    (Finite(c1, e1), Finite(c2, e2)) => compare_finite(c1, e1, c2, e2)
    _ => unit(rank_of_num(a).compare(rank_of_num(b)))
  }
}
