///|
/// The most digits a PartiQL decimal keeps (partiql-tests basic.ion,
/// `decimalRoundUp` and `decimalRoundDown`).
let max_decimal_digits : Int = 38

///|

///|
fn pow10(n : Int) -> @bigint.BigInt {
  @bigint.BigInt::from_int(10).pow(@bigint.BigInt::from_int(n))
}

///|
fn is_negative_int(n : @bigint.BigInt) -> Bool {
  n.compare_int(0) < 0
}

///|
fn abs_int(n : @bigint.BigInt) -> @bigint.BigInt {
  if is_negative_int(n) {
    -n
  } else {
    n
  }
}

///|
fn digit_count(n : @bigint.BigInt) -> Int {
  abs_int(n).to_string().length()
}

///|
/// Rounds a decimal to 38 significant digits, half to even.
pub fn round_decimal(d : @ion_core.Decimal) -> @ion_core.Decimal {
  let digits = d.coefficient().to_string()
  let negative = digits.has_prefix("-")
  let magnitude = if negative {
    digits.view(start_offset=1).to_owned()
  } else {
    digits
  }
  let drop = magnitude.length() - max_decimal_digits
  if drop <= 0 {
    return d
  }
  let kept = @bigint.BigInt::from_string(
    magnitude.view(end_offset=max_decimal_digits).to_owned(),
  )
  let rest = magnitude.view(start_offset=max_decimal_digits).to_owned()
  let half = "5" + "0".repeat(drop - 1)
  let c = rest.lexical_compare(half)
  let up = if c < 0 {
    false
  } else if c > 0 {
    true
  } else {
    kept % @bigint.BigInt::from_int(2) == @bigint.BigInt::from_int(1)
  }
  let mut rounded = if up { kept + @bigint.BigInt::from_int(1) } else { kept }
  let mut exponent = d.exponent() + drop
  // A carry out of 38 nines gives 10^38 (39 digits): renormalize.
  if rounded.to_string().length() > max_decimal_digits {
    rounded = rounded / @bigint.BigInt::from_int(10)
    exponent += 1
  }
  let signed = if negative { -rounded } else { rounded }
  @ion_core.Decimal::new(signed, exponent)
}

///|
/// The widest gap between the exponents of two decimals that `+` and `-`
/// align (a bigger one would need a coefficient of that many digits).
let max_exponent_gap : Int = 100000

///|
/// Both coefficients at the smaller exponent, and that exponent.
fn aligned(
  a : @ion_core.Decimal,
  b : @ion_core.Decimal,
) -> (@bigint.BigInt, @bigint.BigInt, Int) raise OpFailure {
  let gap = (a.exponent() - b.exponent()).abs()
  if gap > max_exponent_gap {
    raise DataFailure("decimals with exponents too far apart")
  }
  let e = a.exponent().min(b.exponent())
  (
    a.coefficient() * pow10(a.exponent() - e),
    b.coefficient() * pow10(b.exponent() - e),
    e,
  )
}

///|
fn decimal_add(
  a : @ion_core.Decimal,
  b : @ion_core.Decimal,
) -> @ion_core.Decimal raise OpFailure {
  let (x, y, e) = aligned(a, b)
  round_decimal(@ion_core.Decimal::new(x + y, e))
}

///|
fn decimal_sub(
  a : @ion_core.Decimal,
  b : @ion_core.Decimal,
) -> @ion_core.Decimal raise OpFailure {
  let (x, y, e) = aligned(a, b)
  round_decimal(@ion_core.Decimal::new(x - y, e))
}

///|
fn decimal_mul(
  a : @ion_core.Decimal,
  b : @ion_core.Decimal,
) -> @ion_core.Decimal {
  round_decimal(
    @ion_core.Decimal::new(
      a.coefficient() * b.coefficient(),
      a.exponent() + b.exponent(),
    ),
  )
}

///|
/// a / b to 38 significant digits, half even (partiql-tests nary-operators.ion,
/// `repeatingDecimal`). Trailing zeros are
/// dropped down to the exponent `a.exponent - b.exponent`, so that an exact
/// quotient keeps its natural scale (`6.0 / 3` is `2`, `1.0 / 4` is `0.25`).
fn decimal_div(
  a : @ion_core.Decimal,
  b : @ion_core.Decimal,
) -> @ion_core.Decimal raise OpFailure {
  if b.is_zero() {
    raise DataFailure("division by zero")
  }
  let preferred = a.exponent() - b.exponent()
  let negative = is_negative_int(a.coefficient()) !=
    is_negative_int(b.coefficient())
  let na = abs_int(a.coefficient())
  let nb = abs_int(b.coefficient())
  if na.is_zero() {
    return @ion_core.Decimal::new(na, preferred)
  }
  // Scale the dividend so that the integer quotient has at least 36 digits.
  let shift = (max_decimal_digits + 2 + digit_count(nb) - digit_count(na)).max(
    0,
  )
  let scaled = na * pow10(shift)
  let q = scaled / nb
  let inexact = !(scaled % nb).is_zero()
  let mut exponent = preferred - shift
  let mut digits = q
  let drop = digit_count(q) - max_decimal_digits
  if drop > 0 {
    let unit = pow10(drop)
    let kept = q / unit
    let twice = q % unit * @bigint.BigInt::from_int(2)
    let c = twice.compare(unit)
    let odd = (kept % @bigint.BigInt::from_int(2)).compare_int(0) != 0
    let up = c > 0 || (c == 0 && (inexact || odd))
    digits = if up { kept + @bigint.BigInt::from_int(1) } else { kept }
    exponent += drop
    if digit_count(digits) > max_decimal_digits {
      digits = digits / @bigint.BigInt::from_int(10)
      exponent += 1
    }
  }
  let ten = @bigint.BigInt::from_int(10)
  while exponent < preferred && (digits % ten).is_zero() {
    digits = digits / ten
    exponent += 1
  }
  @ion_core.Decimal::new(if negative { -digits } else { digits }, exponent)
}

///|
/// The remainder of a / b, with the sign of the dividend.
fn decimal_rem(
  a : @ion_core.Decimal,
  b : @ion_core.Decimal,
) -> @ion_core.Decimal raise OpFailure {
  if b.is_zero() {
    raise DataFailure("division by zero")
  }
  let e = a.exponent().min(b.exponent())
  let ma = a.coefficient() * pow10(a.exponent() - e)
  let mb = b.coefficient() * pow10(b.exponent() - e)
  let r = abs_int(ma) % abs_int(mb)
  @ion_core.Decimal::new(if is_negative_int(ma) { -r } else { r }, e)
}

///|
/// A decimal from its text, with an optional exponent (`2.25e-1`); in PartiQL
/// a number with an exponent is a decimal (partiql-tests nary-operators.ion,
/// `subtractionOutOfAllowedPrecision`, and extended int.ion).
pub fn parse_decimal(text : String) -> @ion_core.Decimal? {
  let parts = text.to_lower().split("e").map(p => p.to_owned()).collect()
  if parts.length() == 0 || parts.length() > 2 {
    return None
  }
  let mantissa = try @ion_core.Decimal::parse(parts[0]) catch {
    _ => return None
  } noraise {
    d => d
  }
  if parts.length() == 1 {
    return Some(mantissa)
  }
  let digits = if parts[1].has_prefix("+") {
    parts[1].view(start_offset=1).to_owned()
  } else {
    parts[1]
  }
  let exponent = try @string.parse_int(digits) catch {
    _ => return None
  } noraise {
    n => n
  }
  Some(
    @ion_core.Decimal::new(
      mantissa.coefficient(),
      mantissa.exponent() + exponent,
    ),
  )
}
