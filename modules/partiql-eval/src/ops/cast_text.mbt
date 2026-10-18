// CAST to character strings and LOBs, and the text of a value (spec M4d2
// §5.3, §5.5).

///|
fn padded(n : Int64, width : Int32) -> String {
  n.to_string().pad_start(width, '0')
}

///|
/// `digits` with a point after the first digit, as a mantissa.
fn mantissa(digits : String) -> String {
  if digits.length() == 1 {
    digits
  } else {
    digits.view(end_offset=1).to_owned() +
    "." +
    digits.view(start_offset=1).to_owned()
  }
}

///|
/// An exact decimal as plain digits with the scale of the value (`1.50`,
/// `1000` for `1d3`). A value outside the range of DECIMAL(38), by its
/// adjusted exponent, is in scientific form, so that the text stays short.
/// Zero has no sign.
fn decimal_text(d : @ion_core.Decimal) -> String {
  let c = d.coefficient()
  let e = d.exponent().to_int64()
  if c.is_zero() && e >= 0L {
    return "0"
  }
  let digits = abs_int(c).to_string()
  let sign = if is_negative_int(c) { "-" } else { "" }
  let n = digits.length()
  let adjusted = n.to_int64() - 1L + e
  if adjusted < -39L || adjusted > 37L {
    return "\{sign}\{mantissa(digits)}E\{adjusted}"
  }
  if e >= 0L {
    return sign + digits + "0".repeat(e.to_int())
  }
  let k = (-e).to_int()
  if n > k {
    sign +
    digits.view(end_offset=n - k).to_owned() +
    "." +
    digits.view(start_offset=n - k).to_owned()
  } else {
    sign + "0." + "0".repeat(k - n) + digits
  }
}

///|
/// A float in SQL approximate form with the shortest digits that give it
/// back (`1.5E0`); NaN and the infinities in their Ion spellings.
fn float_text(f : Double) -> String {
  if f.is_nan() {
    return "nan"
  }
  if f.is_pos_inf() {
    return "+inf"
  }
  if f.is_neg_inf() {
    return "-inf"
  }
  let sign = if f.reinterpret_as_int64() < 0L { "-" } else { "" }
  if f == 0.0 {
    return sign + "0E0"
  }
  guard parse_decimal(f.abs().to_string()) is Some(shortest) else {
    return f.to_string()
  }
  let mut c = shortest.coefficient()
  let mut e = shortest.exponent()
  while (c % 10N).is_zero() {
    c = c / 10N
    e += 1
  }
  let digits = c.to_string()
  "\{sign}\{mantissa(digits)}E\{digits.length() - 1 + e}"
}

///|
fn date_text(d : @value.Date) -> String {
  let year = if d.year < 0 {
    "-" + padded((-d.year).to_int64(), 4)
  } else {
    padded(d.year.to_int64(), 4)
  }
  "\{year}-\{padded(d.month.to_int64(), 2)}-\{padded(d.day.to_int64(), 2)}"
}

///|
/// `HH:MM:SS`, then exactly the precision of the value in fraction digits,
/// then the offset when the time has one.
fn time_text(t : @value.Time) -> String {
  let clock = "\{padded(t.hour.to_int64(), 2)}:\{padded(t.minute.to_int64(), 2)}:\{padded(t.second.to_int64(), 2)}"
  let fraction = if t.precision > 0 {
    "." +
    padded(t.nanos.to_int64(), 9).view(end_offset=t.precision.min(9)).to_owned()
  } else {
    ""
  }
  let offset = match t.offset {
    None => ""
    Some(minutes) => {
      let sign = if minutes < 0 { "-" } else { "+" }
      let m = minutes.abs()
      "\{sign}\{padded((m / 60).to_int64(), 2)}:\{padded((m % 60).to_int64(), 2)}"
    }
  }
  clock + fraction + offset
}

///|
/// `(k)` when `n` has more digits than the default precision `default`.
fn precision_text(digits : Int32, default : Int32) -> String {
  if digits > default {
    "(\{digits})"
  } else {
    ""
  }
}

///|
/// `INTERVAL 'Y-M' YEAR TO MONTH`, with a leading `-` in the string when
/// negative. The value keeps only its class, so the literal names the whole
/// class; a leading precision above the default 2 is written out.
fn ym_text(i : @value.IntervalYM) -> String {
  let months = big64(i.months)
  let sign = if is_negative_int(months) { "-" } else { "" }
  let m = abs_int(months)
  let years = m / 12N
  "INTERVAL '\{sign}\{years}-\{m % 12N}' YEAR\{precision_text(digit_count(years), 2)} TO MONTH"
}

///|
/// `INTERVAL 'D HH:MM:SS[.f]' DAY TO SECOND` with the fewest fraction digits,
/// a leading `-` in the string when negative, and the leading (default 2)
/// and fractional (default 6) precisions written out when larger.
fn dt_text(i : @value.IntervalDT) -> String {
  let n = dt_nanos(i)
  let sign = if is_negative_int(n) { "-" } else { "" }
  let a = abs_int(n)
  let days = a / nanos_per_day
  let rest = (a % nanos_per_day).to_int64()
  let seconds = rest / 1000000000L
  let nanos = (rest % 1000000000L).to_int()
  let digits = if nanos == 0 { 0 } else { needed_precision(nanos) }
  let fraction = if nanos == 0 {
    ""
  } else {
    "." + padded(nanos.to_int64(), 9).view(end_offset=digits).to_owned()
  }
  let clock = "\{padded(seconds / 3600L, 2)}:\{padded(seconds % 3600L / 60L, 2)}:\{padded(seconds % 60L, 2)}"
  "INTERVAL '\{sign}\{days} \{clock}\{fraction}' DAY\{precision_text(digit_count(days), 2)} TO SECOND\{precision_text(digits, 6)}"
}

///|
/// The text of a scalar value as CAST to a character string gives it (spec
/// M4d2 §5.5); `None` for a kind that has no text. A datetime or interval is
/// an SQL <literal> (SQL 6.13: "the shortest character string that conforms
/// to the definition of <literal>"), so that CAST reads it back.
fn display_text(x : @value.Value) -> String? {
  match x {
    Bool(b) => Some(if b { "TRUE" } else { "FALSE" })
    Int(n) => Some(n.to_string())
    BigInt(n) => Some(n.to_string())
    Decimal(d) => Some(decimal_text(d))
    Float(f) => Some(float_text(f))
    Date(d) => Some("DATE '\{date_text(d)}'")
    Time(t) => Some("TIME '\{time_text(t)}'")
    Timestamp(ts) =>
      Some("TIMESTAMP '\{date_text(ts.date)} \{time_text(ts.time)}'")
    IntervalYM(i) => Some(ym_text(i))
    IntervalDT(i) => Some(dt_text(i))
    _ => None
  }
}

///|
/// `text` in at most `n` code points. Character text is cut (SQL gives only
/// a warning); the text of another kind that does not fit is out of range
/// (SQL 22001).
fn fit_text(
  text : String,
  n : Int32,
  character : Bool,
  name : String,
) -> String raise OpFailure {
  let chars = text.to_array()
  if chars.length() <= n {
    text
  } else if character {
    String::from_array(chars[:n])
  } else {
    raise DataFailure("'\{text}' is longer than \{name}")
  }
}

///|
fn to_text(x : @value.Value, kind : TextKind) -> @value.Value raise OpFailure {
  let name = target_name(Text(kind))
  let (text, character) = match x {
    String(s) => (s, true)
    Clob(b) => {
      let s = @utf8.decode(b[:]) catch {
        _ => raise TypeFailure("a CLOB that is not UTF-8")
      }
      (s, true)
    }
    _ =>
      match display_text(x) {
        Some(t) => (t, false)
        None => raise TypeFailure("CAST of \{kind_name(x)} to \{name}")
      }
  }
  match kind {
    String => @value.Value::from_string(text)
    Varchar(n) => @value.Value::from_string(fit_text(text, n, character, name))
    Char(n) => {
      let fitted = fit_text(text, n, character, name)
      @value.Value::from_string(fitted + " ".repeat(n - fitted.char_length()))
    }
  }
}

///|
/// CLOB from text (UTF-8) or a LOB; BLOB from a LOB (spec M4d2 §5.3).
fn to_lob(
  x : @value.Value,
  target : CastTarget,
) -> @value.Value raise OpFailure {
  match (x, target) {
    (String(s), Clob) => @value.Value::from_clob(@utf8.encode(s.view()))
    (Clob(b) | Blob(b), Clob) => @value.Value::from_clob(b)
    (Clob(b) | Blob(b), Blob) => @value.Value::from_blob(b)
    _ => raise TypeFailure("CAST of \{kind_name(x)} to \{target_name(target)}")
  }
}
