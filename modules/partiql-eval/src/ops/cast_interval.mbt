// CAST to INTERVAL (spec M4d2 §5.4).

///|
/// The interval `v` in the fields of `q` (SQL92 6.10 GR 12): cut toward
/// zero to whole units of the last field (or of the fractional precision for
/// SECOND); a leading field with more digits than its precision (default
/// 2) is an interval field overflow.
fn interval_to_interval(
  v : @value.Value,
  q : @ast.IntervalQualifier,
) -> @value.Value raise OpFailure {
  let leading = q.start_precision.unwrap_or(2)
  let last = q.end.unwrap_or(q.start)
  let overflow = DataFailure(
    "an interval leading field of more than \{leading} digits",
  )
  match (v, q.start) {
    (IntervalYM(i), Year | Month) => {
      let m = big64(i.months)
      let kept = if last is Year { m - m % 12N } else { m }
      let lead = if q.start is Year { kept / 12N } else { kept }
      if !within_digits(abs_int(lead), leading) {
        raise overflow
      }
      ym_value(kept)
    }
    (IntervalDT(i), Day | Hour | Minute | Second) => {
      let n = dt_nanos(i)
      let step = if last is Second {
        pow10(9 - q.fractional_precision.unwrap_or(6))
      } else {
        field_nanos(last)
      }
      let kept = n - n % step
      if !within_digits(abs_int(kept) / field_nanos(q.start), leading) {
        raise overflow
      }
      dt_value(kept)
    }
    _ => raise TypeFailure("CAST of an interval of the other class")
  }
}

///|
/// The units of the field of a one-field qualifier, in months (year-month)
/// or nanoseconds (day-time).
fn field_units(f : @ast.DatetimeField) -> @bigint.BigInt {
  match f {
    Year => 12N
    Month => 1N
    _ => field_nanos(f)
  }
}

///|
/// An exact number as `n` units of the one field of `q` (SQL92 6.10 GR 12a).
/// A fraction is cut toward zero by the interval rule.
fn number_to_interval(
  d : @ion_core.Decimal,
  q : @ast.IntervalQualifier,
) -> @value.Value raise OpFailure {
  if q.end is Some(end) && end != q.start {
    raise TypeFailure("CAST of a number to an interval of more than one field")
  }
  let c = d.coefficient() * field_units(q.start)
  let e = d.exponent().to_int64()
  let total = if e >= 0L {
    if digit_count(c).to_int64() + e > 40L {
      raise DataFailure("a number out of the range of the interval")
    }
    c * pow10(e.to_int())
  } else if -e > (digit_count(c) + 1).to_int64() {
    0N
  } else {
    c / pow10((-e).to_int())
  }
  let v = if q.start is (Year | Month) {
    ym_value(total)
  } else {
    dt_value(total)
  }
  interval_to_interval(v, q)
}

///|
fn to_interval(
  x : @value.Value,
  q : @ast.IntervalQualifier,
) -> @value.Value raise OpFailure {
  match x {
    IntervalYM(_) | IntervalDT(_) => interval_to_interval(x, q)
    // Read the literal with room for any digits, then cast it, so that a
    // leading field that is too long is an overflow (SQL 22015), not a
    // text that is not valid.
    String(s) => {
      let wide : @ast.IntervalQualifier = {
        ..q,
        start_precision: Some(18),
        fractional_precision: Some(9),
      }
      interval_to_interval(
        parse_interval(trimmed(s), negative=false, qualifier=wide),
        q,
      )
    }
    Int(n) => number_to_interval(@ion_core.Decimal::new(big64(n), 0), q)
    BigInt(n) => number_to_interval(@ion_core.Decimal::new(n, 0), q)
    Decimal(d) => number_to_interval(d, q)
    _ => raise TypeFailure("CAST of \{kind_name(x)} to INTERVAL")
  }
}
