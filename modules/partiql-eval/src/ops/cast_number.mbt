// CAST to BOOL and the number types (spec M4d2 §5.2).

///|
/// The number a source value stands for: BOOL is 1 or 0, text is read by
/// `numeric_text`. An interval has no number in this version: its value does
/// not keep the field it counts (spec M4d2 §2, Q15).
fn numeric_source(x : @value.Value, target : String) -> Num raise OpFailure {
  match x {
    Bool(b) => Whole(if b { 1N } else { 0N })
    String(s) => numeric_text(s)
    IntervalYM(_) | IntervalDT(_) =>
      raise Unsupported("CAST of an interval to \{target}")
    _ =>
      match number(x) {
        Some(n) => n
        None => raise TypeFailure("CAST of \{kind_name(x)} to \{target}")
      }
  }
}

///|
/// `x` as an exact decimal. A float becomes the decimal of its shortest
/// text (spec M4d2 §2, Q9); NaN and the infinities have no exact value.
fn exact_of(n : Num) -> @ion_core.Decimal raise OpFailure {
  match n {
    Whole(w) => @ion_core.Decimal::new(w, 0)
    Exact(d) => d
    Approx(f) => {
      if f.is_nan() || f.is_inf() {
        raise DataFailure("NaN or infinity has no exact value")
      }
      match parse_decimal(f.to_string()) {
        Some(d) => d
        None => raise DataFailure("a float without a decimal")
      }
    }
  }
}

///|
/// `c / 10^drop`, rounded half to even. `drop` is at least 1.
fn shift_round(c : @bigint.BigInt, drop : Int32) -> @bigint.BigInt {
  // |c| < 10^digits <= 10^(drop - 2): the quotient is under 0.01.
  if drop > digit_count(c) + 1 {
    return 0N
  }
  let unit = pow10(drop)
  let q = c / unit
  let r = c - q * unit
  let twice = abs_int(r) * 2N
  let c2 = twice.compare(unit)
  let up = c2 > 0 || (c2 == 0 && !(q % 2N).is_zero())
  if !up {
    q
  } else if is_negative_int(c) {
    q - 1N
  } else {
    q + 1N
  }
}

///|
/// The integer nearest to `d`, ties to even. A value of more than 40
/// digits is out of the range of every integer type.
fn decimal_to_integer(d : @ion_core.Decimal) -> @bigint.BigInt raise OpFailure {
  let c = d.coefficient()
  if c.is_zero() {
    return 0N
  }
  let e = d.exponent().to_int64()
  if e >= 0L {
    if digit_count(c).to_int64() + e > 40L {
      raise DataFailure("a number out of the integer range")
    }
    c * pow10(e.to_int())
  } else if -e > (digit_count(c) + 1).to_int64() {
    0N
  } else {
    shift_round(c, (-e).to_int())
  }
}

///|
fn width_range(width : IntWidth) -> (Int64, Int64) {
  match width {
    Bits8 => (-128L, 127L)
    Bits16 => (-32768L, 32767L)
    Bits32 => (-2147483648L, 2147483647L)
    Bits64 => (-9223372036854775808L, 9223372036854775807L)
  }
}

///|
fn to_integer(
  x : @value.Value,
  width : IntWidth,
) -> @value.Value raise OpFailure {
  let name = target_name(Integer(width))
  let n = match numeric_source(x, name) {
    Whole(n) => n
    other => decimal_to_integer(exact_of(other))
  }
  let (low, high) = width_range(width)
  if n.compare_int64(low) < 0 || n.compare_int64(high) > 0 {
    raise DataFailure("\{n} is out of the range of \{name}")
  }
  Int(n.to_int64())
}

///|
fn is_zero_number(n : Num) -> Bool {
  match n {
    Whole(w) => w.is_zero()
    Exact(d) => d.coefficient().is_zero()
    Approx(f) => f == 0.0
  }
}

///|
/// BOOL: text is TRUE, FALSE or UNKNOWN (NULL) in any case (SQL); a number
/// is FALSE when zero (spec M4d2 §2, Q8). NaN has no truth value.
fn to_bool(x : @value.Value) -> @value.Value raise OpFailure {
  match x {
    Bool(_) => x
    String(s) =>
      match s.trim(chars=" ").to_owned().to_lower() {
        "true" => Bool(true)
        "false" => Bool(false)
        "unknown" => Null
        _ => raise TypeFailure("'\{s}' is not a boolean")
      }
    _ =>
      match number(x) {
        Some(Approx(f)) if f.is_nan() => raise TypeFailure("NaN as BOOL")
        Some(n) => Bool(!is_zero_number(n))
        None => raise TypeFailure("CAST of \{kind_name(x)} to BOOL")
      }
  }
}

///|
/// DECIMAL(p, s): `d` rounded half to even to scale `s`; more than `p - s`
/// integer digits is out of range.
fn fixed_decimal(
  d : @ion_core.Decimal,
  precision : Int32,
  scale : Int32,
) -> @ion_core.Decimal raise OpFailure {
  let c = d.coefficient()
  if c.is_zero() {
    return @ion_core.Decimal::new(0N, -scale)
  }
  let too_long = DataFailure(
    "a value out of the range of DECIMAL(\{precision},\{scale})",
  )
  let e = d.exponent().to_int64()
  let target = -scale.to_int64()
  // Integer digits before rounding; rounding adds at most one.
  if digit_count(c).to_int64() + e > (precision - scale).to_int64() + 1L {
    raise too_long
  }
  let rounded = if e >= target {
    c * pow10((e - target).to_int())
  } else if target - e > (digit_count(c) + 1).to_int64() {
    0N
  } else {
    shift_round(c, (target - e).to_int())
  }
  if !rounded.is_zero() && digit_count(rounded) > precision {
    raise too_long
  }
  @ion_core.Decimal::new(rounded, -scale)
}

///|
fn to_decimal_target(
  x : @value.Value,
  scale : Scale,
) -> @value.Value raise OpFailure {
  let d = exact_of(numeric_source(x, target_name(Decimal(scale))))
  match scale {
    Unconstrained => Decimal(round_decimal(d))
    Fixed(precision~, scale~) => Decimal(fixed_decimal(d, precision, scale))
  }
}

///|
/// The binary64 value nearest to `d` (`parse_double` rounds correctly).
fn exact_double(d : @ion_core.Decimal) -> Double raise OpFailure {
  let f = @string.parse_double("\{d.coefficient()}e\{d.exponent()}") catch {
    _ => raise DataFailure("a number out of the range of DOUBLE PRECISION")
  }
  if f.is_inf() {
    raise DataFailure("a number out of the range of DOUBLE PRECISION")
  }
  f
}

///|
/// `f` rounded to binary32. A finite value that rounds to infinity is out of
/// the range of REAL.
fn to_real(f : Double) -> Double raise OpFailure {
  let r = Float::from_double(f).to_double()
  if r.is_inf() && !f.is_inf() {
    raise DataFailure("\{f} is out of the range of REAL")
  }
  r
}

///|
/// The binary32 value nearest to the exact `d`, given `f`, the binary64 value
/// nearest to `d`. Rounding `f` again is wrong only when `f` lies exactly
/// halfway between two binary32 values: then the side of `d` decides.
fn nearest_real(d : @ion_core.Decimal, f : Double) -> Double raise OpFailure {
  let r = to_real(f)
  let other = 2.0 * f - r
  if r == f || other == r || Float::from_double(other).to_double() != other {
    return r
  }
  // Both values at one exponent; `Decimal::compare` gives no order here.
  let (x, y, _) = aligned(d, exact_decimal(f))
  let c = x.compare(y)
  if c > 0 {
    if r > other {
      r
    } else {
      other
    }
  } else if c < 0 {
    if r < other {
      r
    } else {
      other
    }
  } else {
    r
  }
}

///|
fn to_float_target(
  x : @value.Value,
  width : FloatWidth,
) -> @value.Value raise OpFailure {
  match numeric_source(x, target_name(Float(width))) {
    Approx(f) =>
      Float(
        match width {
          Double => f
          Real => to_real(f)
        },
      )
    n => {
      let d = exact_of(n)
      let f = exact_double(d)
      Float(
        match width {
          Double => f
          Real => nearest_real(d, f)
        },
      )
    }
  }
}
