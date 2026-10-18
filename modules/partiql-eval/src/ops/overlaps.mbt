// OVERLAPS (SQL-92 8.11; spec M4d3 §4.5).

///|
/// The two elements of an OVERLAPS operand: a list or a bag (stored order) of
/// exactly two elements; the first NULL, MISSING or a datetime, the second
/// also an interval. MISSING elements act as NULL.
fn period_elements(
  v : @value.Value,
) -> (@value.Value, @value.Value) raise OpFailure {
  let items = match v {
    List(xs) => xs
    Bag(b) => Array::from_iter(b.items().iter())
    _ => raise TypeFailure("an OVERLAPS operand must be a list or bag of 2")
  }
  if items.length() != 2 {
    raise TypeFailure("an OVERLAPS operand must have exactly 2 elements")
  }
  let first = boxed(items[0])
  let second = boxed(items[1])
  if !first.is_absent() && !is_datetime(first) {
    raise TypeFailure("the start of an OVERLAPS period must be a datetime")
  }
  if !second.is_absent() && !is_datetime(second) && !is_interval(second) {
    raise TypeFailure(
      "the end of an OVERLAPS period must be a datetime or an interval",
    )
  }
  (
    if first.is_absent() {
      Null
    } else {
      first
    },
    if second.is_absent() {
      Null
    } else {
      second
    },
  )
}

///|
/// Start and end of a period: the second element, or start + interval.
fn period_end(
  start : @value.Value,
  second : @value.Value,
) -> @value.Value raise OpFailure {
  if is_interval(second) {
    if start is Null {
      Null
    } else {
      shift_datetime(start, second, negative=false)
    }
  } else {
    second
  }
}

///|
/// The order of two non-NULL datetimes of one family; `None` when either is
/// NULL.
fn period_order(
  a : @value.Value,
  b : @value.Value,
  zone : ZoneOffset,
) -> Int32? raise OpFailure {
  if a is Null || b is Null {
    return None
  }
  Some(zoned_instant(a, zone).compare(zoned_instant(b, zone)))
}

///|
fn and3(a : Bool?, b : Bool?) -> Bool? {
  match (a, b) {
    (Some(false), _) | (_, Some(false)) => Some(false)
    (Some(true), Some(true)) => Some(true)
    _ => None
  }
}

///|
fn or3(a : Bool?, b : Bool?) -> Bool? {
  match (a, b) {
    (Some(true), _) | (_, Some(true)) => Some(true)
    (Some(false), Some(false)) => Some(false)
    _ => None
  }
}

///|
fn not3(a : Bool?) -> Bool? {
  a.map(x => !x)
}

///|
/// `x OVERLAPS y`.
pub fn overlaps(
  args : Array[@value.Value],
  zone~ : ZoneOffset,
) -> @value.Value raise OpFailure {
  guard args.length() == 2 else {
    raise DataFailure("OVERLAPS takes 2 operands")
  }
  let x = boxed(args[0])
  let y = boxed(args[1])
  if x is Missing || y is Missing {
    return Missing
  }
  if x is Null || y is Null {
    return Null
  }
  let (d1, second1) = period_elements(x)
  let (d2, second2) = period_elements(y)
  let e1 = period_end(d1, second1)
  let e2 = period_end(d2, second2)
  // Every non-NULL endpoint must be of one family: TIME with TIME, DATE or
  // TIMESTAMP with each other.
  let points = [d1, e1, d2, e2].filter(p => !(p is Null))
  let times = points.iter().all(p => p is Time(_))
  let instants = points.iter().all(p => is_point_in_time(p))
  if !times && !instants {
    raise TypeFailure("OVERLAPS periods of datetimes that do not compare")
  }
  // SQL-92 8.11 GR 3: the earlier endpoint is the start.
  let (s1, t1) = if d1 is Null ||
    (period_order(e1, d1, zone) is Some(c) && c < 0) {
    (e1, d1)
  } else {
    (d1, e1)
  }
  let (s2, t2) = if d2 is Null ||
    (period_order(e2, d2, zone) is Some(c) && c < 0) {
    (e2, d2)
  } else {
    (d2, e2)
  }
  let gt = (a, b) => period_order(a, b, zone).map(c => c > 0)
  let ge = (a, b) => period_order(a, b, zone).map(c => c >= 0)
  let eq = (a, b) => period_order(a, b, zone).map(c => c == 0)
  let ne = (a, b) => period_order(a, b, zone).map(c => c != 0)
  let first = and3(gt(s1, s2), not3(and3(ge(s1, t2), ge(t1, t2))))
  let second = and3(gt(s2, s1), not3(and3(ge(s2, t1), ge(t2, t1))))
  let third = and3(eq(s1, s2), or3(ne(t1, t2), eq(t1, t2)))
  match or3(or3(first, second), third) {
    Some(b) => @value.Value::from_bool(b)
    None => Null
  }
}
