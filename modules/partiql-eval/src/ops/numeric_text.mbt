// SQL numeric text, as CAST reads it (spec M4d2 §4.3).

///|
/// The value of `c` as a digit of `base`, if it is one.
fn digit_of(c : Char, base : Int32) -> Int32? {
  let value = match c {
    '0'..<='9' => c.to_int() - '0'.to_int()
    'a'..<='f' => c.to_int() - 'a'.to_int() + 10
    'A'..<='F' => c.to_int() - 'A'.to_int() + 10
    _ => return None
  }
  if value < base {
    Some(value)
  } else {
    None
  }
}

///|
/// The digits of `base` from `start`, without the `_` separators, and the
/// index after them. A `_` counts only between two digits (SQL:2023).
fn digit_run(
  chars : Array[Char],
  start : Int32,
  base : Int32,
) -> (String, Int32) {
  let buf = StringBuilder()
  let mut i = start
  while i < chars.length() {
    let c = chars[i]
    if digit_of(c, base) is Some(_) {
      buf.write_char(c)
      i += 1
    } else if c == '_' &&
      i > start &&
      i + 1 < chars.length() &&
      digit_of(chars[i - 1], base) is Some(_) &&
      digit_of(chars[i + 1], base) is Some(_) {
      i += 1
    } else {
      break
    }
  }
  (buf.to_string(), i)
}

///|
fn not_a_number(text : String) -> OpFailure {
  TypeFailure("'\{text}' is not a number")
}

///|
/// A number from SQL text: leading and trailing spaces (U+0020 only) are
/// trimmed, then an optional sign and one of: `0x`/`0o`/`0b` digits (an
/// integer); digits with an optional fraction (an exact decimal); the same
/// with an exponent (also exact, as a PartiQL number literal); `nan`, `inf`
/// (any case; only `inf` takes a sign), the only approximate forms.
fn numeric_text(text : String) -> Num raise OpFailure {
  let chars = text.trim(chars=" ").to_owned().to_array()
  let n = chars.length()
  let signed = n > 0 && (chars[0] == '-' || chars[0] == '+')
  let negative = n > 0 && chars[0] == '-'
  let i = if signed { 1 } else { 0 }
  match String::from_array(chars[i:]).to_lower() {
    "nan" if !signed => return Approx(@double.not_a_number)
    "inf" =>
      return Approx(
        if negative {
          @double.neg_infinity
        } else {
          @double.infinity
        },
      )
    _ => ()
  }
  if n >= i + 2 && chars[i] == '0' {
    let base = match chars[i + 1] {
      'x' | 'X' => 16
      'o' | 'O' => 8
      'b' | 'B' => 2
      _ => 0
    }
    if base > 0 {
      let (digits, end) = digit_run(chars, i + 2, base)
      if digits.is_empty() || end != n {
        raise not_a_number(text)
      }
      let value = @bigint.BigInt::from_string(digits, radix=base)
      return Whole(if negative { -value } else { value })
    }
  }
  let (whole, after_whole) = digit_run(chars, i, 10)
  let mut j = after_whole
  let mut fraction = ""
  if j < n && chars[j] == '.' {
    let (digits, end) = digit_run(chars, j + 1, 10)
    fraction = digits
    j = end
  }
  if whole.is_empty() && fraction.is_empty() {
    raise not_a_number(text)
  }
  if j < n && (chars[j] == 'e' || chars[j] == 'E') {
    let mut k = j + 1
    let exponent_sign = if k < n && (chars[k] == '-' || chars[k] == '+') {
      k += 1
      chars[k - 1].to_string()
    } else {
      ""
    }
    let (exponent, end) = digit_run(chars, k, 10)
    if exponent.is_empty() || end != n {
      raise not_a_number(text)
    }
    // An exponent does not make the number approximate: PartiQL reads a
    // number literal with an exponent as a DECIMAL, so the digits stay
    // exact and each target rounds once (spec M4d2 §4.3).
    let magnitude = @bigint.BigInt::from_string(exponent)
    let shift = (if exponent_sign == "-" { -magnitude } else { magnitude }) -
      @bigint.BigInt::from_int(fraction.length())
    if shift.compare_int(2147483647) > 0 || shift.compare_int(-2147483648) < 0 {
      raise DataFailure("the exponent of '\{text}' is out of range")
    }
    return Exact(signed_decimal(negative, whole + fraction, shift.to_int()))
  }
  if j != n {
    raise not_a_number(text)
  }
  Exact(signed_decimal(negative, whole + fraction, -fraction.length()))
}

///|
/// The decimal `digits` × 10^`exponent`, negated when `negative`.
fn signed_decimal(
  negative : Bool,
  digits : String,
  exponent : Int32,
) -> @ion_core.Decimal {
  let coefficient = @bigint.BigInt::from_string(digits)
  @ion_core.Decimal::new(
    if negative {
      -coefficient
    } else {
      coefficient
    },
    exponent,
  )
}
