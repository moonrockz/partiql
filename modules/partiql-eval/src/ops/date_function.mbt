// DATE_ADD and DATE_DIFF (spec M4d3 §4.3, §4.4).

///|
/// Whether a datetime has the field (SQL-92 6.14 SR 3): DATE has YEAR,
/// MONTH and DAY; TIME has HOUR, MINUTE and SECOND; TIMESTAMP has all six.
fn has_field(f : @ast.DatetimeField, x : @value.Value) -> Bool {
  match (f, x) {
    (Year | Month | Day, Date(_) | Timestamp(_)) => true
    (Hour | Minute | Second, Time(_) | Timestamp(_)) => true
    _ => false
  }
}

///|
/// `x` plus `n` units of `f`. The result keeps the type, precision and
/// offset of `x`.
fn add_units(
  f : @ast.DatetimeField,
  n : @value.Value,
  x : @value.Value,
) -> @value.Value raise OpFailure {
  let count = match n {
    Int(i) => big64(i)
    BigInt(b) => b
    _ => raise TypeFailure("the quantity of DATE_ADD must be an integer")
  }
  if !has_field(f, x) {
    raise TypeFailure("DATE_ADD \{field_name(f)} to \{kind_name(x)}")
  }
  match f {
    Year | Month => {
      let months = if f is Year { count * 12N } else { count }
      if !fits_int64(months) {
        raise DataFailure("datetime field overflow in DATE_ADD")
      }
      match x {
        Date(d) => Date(date_add_months(d, months.to_int64()))
        Timestamp(ts) =>
          Timestamp(
            @value.Timestamp::new(
              date_add_months(ts.date, months.to_int64()),
              ts.time,
            ),
          )
        _ => raise TypeFailure("DATE_ADD \{field_name(f)} to \{kind_name(x)}")
      }
    }
    _ => {
      let nanos = count * field_nanos(f)
      match x {
        Date(d) => Date(date_shift(d, nanos))
        Timestamp(ts) => Timestamp(timestamp_shift(ts, nanos))
        Time(t) => Time(time_shift(t, nanos))
        _ => raise TypeFailure("DATE_ADD \{field_name(f)} to \{kind_name(x)}")
      }
    }
  }
}

///|
/// `DATE_ADD(f, n, x)`.
pub fn date_add(
  field : @ast.DatetimeField,
  args : Array[@value.Value],
) -> @value.Value raise OpFailure {
  apply("DATE_ADD", [Integer, Datetime], args, xs => {
    add_units(field, xs[0], xs[1])
  })
}
