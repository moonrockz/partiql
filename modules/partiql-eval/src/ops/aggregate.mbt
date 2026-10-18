// Aggregate functions over values (spec M4c §3.3, §3.4, §6): the folds
// behind COUNT, SUM, AVG, MIN, MAX, ANY, SOME and EVERY, in the SQL and the
// COLL_ forms.

///|
/// The values an aggregate reads: each value as the PartiQL value it stands
/// for, without NULL and MISSING; with `distinct`, the first of each class of
/// grouping-equivalent values (`eqg`), found by bucket (`group_key`).
fn present(
  values : Iter[@value.Value],
  distinct : Bool,
) -> Array[@value.Value] raise OpFailure {
  let seen : Map[String, Array[@value.Value]] = Map([])
  let out = []
  for v in values {
    let x = boxed(v)
    if x is (Null | Missing) {
      continue
    }
    if distinct {
      let bucket = seen.get_or_init(@value.group_key(x), () => [])
      if bucket.iter().any(y => @value.eqg(x, y)) {
        continue
      }
      bucket.push(x)
    }
    out.push(x)
  }
  out
}

///|
fn numbers(
  xs : Array[@value.Value],
  name : String,
) -> Array[Num] raise OpFailure {
  let out = []
  for x in xs {
    match number(x) {
      Some(n) => out.push(n)
      None => raise TypeFailure("\{name} needs numbers")
    }
  }
  out
}

///|
/// The sum of integers, when every number is an integer.
fn whole_sum(nums : Array[Num]) -> @bigint.BigInt? {
  let mut sum = @bigint.BigInt::from_int(0)
  for n in nums {
    match n {
      Whole(w) => sum = sum + w
      _ => return None
    }
  }
  Some(sum)
}

///|
/// The sum as a decimal: a float joins as the decimal of its shortest text.
fn decimal_sum(nums : Array[Num]) -> @ion_core.Decimal raise OpFailure {
  let mut sum = @ion_core.Decimal::Decimal(@bigint.BigInt::from_int(0), 0)
  for n in nums {
    sum = decimal_add(sum, to_decimal(n))
  }
  sum
}

///|
pub fn count_values(
  values : Iter[@value.Value],
  distinct~ : Bool,
) -> @value.Value raise OpFailure {
  Int(present(values, distinct).length().to_int64())
}

///|
/// SUM: an integer when every value is an integer (the range is checked
/// once, at the end), else a decimal.
pub fn sum_values(
  values : Iter[@value.Value],
  distinct~ : Bool,
) -> @value.Value raise OpFailure {
  let xs = present(values, distinct)
  if xs.is_empty() {
    return Null
  }
  let nums = numbers(xs, "SUM")
  match whole_sum(nums) {
    Some(sum) => whole_value(sum)
    None => Decimal(decimal_sum(nums))
  }
}

///|
/// AVG: the sum divided by the count, as a decimal (38 digits, half even,
/// natural scale).
pub fn avg_values(
  values : Iter[@value.Value],
  distinct~ : Bool,
) -> @value.Value raise OpFailure {
  let xs = present(values, distinct)
  if xs.is_empty() {
    return Null
  }
  let nums = numbers(xs, "AVG")
  let sum = match whole_sum(nums) {
    Some(s) => @ion_core.Decimal::Decimal(s, 0)
    None => decimal_sum(nums)
  }
  let count = @ion_core.Decimal::Decimal(
    @bigint.BigInt::from_int(xs.length()),
    0,
  )
  Decimal(decimal_div(sum, count))
}

///|
/// The value that `better` prefers over every other, by the total order of
/// ORDER BY; NULL for none.
fn extreme(xs : Array[@value.Value], better : (Int32) -> Bool) -> @value.Value {
  guard xs is [first, .. rest] else { return Null }
  let mut best = first
  for x in rest {
    if better(@value.compare(x, best, nulls=NullsFirst)) {
      best = x
    }
  }
  best
}

///|
pub fn min_values(
  values : Iter[@value.Value],
  distinct~ : Bool,
) -> @value.Value raise OpFailure {
  extreme(present(values, distinct), c => c < 0)
}

///|
pub fn max_values(
  values : Iter[@value.Value],
  distinct~ : Bool,
) -> @value.Value raise OpFailure {
  extreme(present(values, distinct), c => c > 0)
}

///|
fn booleans(
  xs : Array[@value.Value],
  name : String,
) -> Array[Bool] raise OpFailure {
  let out = []
  for x in xs {
    match x {
      Bool(b) => out.push(b)
      _ => raise TypeFailure("\{name} needs booleans")
    }
  }
  out
}

///|
/// ANY (and SOME): TRUE when one value is TRUE.
pub fn any_values(
  values : Iter[@value.Value],
  distinct~ : Bool,
) -> @value.Value raise OpFailure {
  let bs = booleans(present(values, distinct), "ANY")
  if bs.is_empty() {
    Null
  } else {
    Bool(bs.iter().any(b => b))
  }
}

///|
/// EVERY: TRUE when every value is TRUE.
pub fn every_values(
  values : Iter[@value.Value],
  distinct~ : Bool,
) -> @value.Value raise OpFailure {
  let bs = booleans(present(values, distinct), "EVERY")
  if bs.is_empty() {
    Null
  } else {
    Bool(bs.iter().all(b => b))
  }
}
