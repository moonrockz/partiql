///|
/// Whether two values can be ordered: two numbers, two strings, two
/// datetimes of the same kind or two booleans.
fn orderable(x : @value.Value, y : @value.Value) -> Bool {
  match (x, y) {
    (Bool(_), Bool(_))
    | (String(_), String(_))
    | (Date(_), Date(_))
    | (Time(_), Time(_))
    | (Timestamp(_), Timestamp(_))
    | (Date(_), Timestamp(_))
    | (Timestamp(_), Date(_))
    | (IntervalYM(_), IntervalYM(_))
    | (IntervalDT(_), IntervalDT(_)) => true
    _ => number(x) is Some(_) && number(y) is Some(_)
  }
}

///|
fn is_nan(v : @value.Value) -> Bool {
  v is Float(f) && f.is_nan()
}

///|
/// Orders two values; `holds` decides from the sign of the comparison. Any NaN
/// makes every ordering false.
fn ordered(
  a : @value.Value,
  b : @value.Value,
  holds : (Int) -> Bool,
) -> @value.Value raise OpFailure {
  let x = boxed(a)
  let y = boxed(b)
  if x is Missing || y is Missing {
    return Missing
  }
  if x is Null || y is Null {
    return Null
  }
  if !orderable(x, y) {
    raise TypeFailure("an ordering of values that cannot be compared")
  }
  if is_nan(x) || is_nan(y) {
    return Bool(false)
  }
  match datetime_order(x, y) {
    Some(c) => Bool(holds(c))
    None => Bool(holds(@value.compare(x, y, nulls=NullsFirst)))
  }
}

///|
pub fn less(a : @value.Value, b : @value.Value) -> @value.Value raise OpFailure {
  ordered(a, b, c => c < 0)
}

///|
pub fn less_eq(
  a : @value.Value,
  b : @value.Value,
) -> @value.Value raise OpFailure {
  ordered(a, b, c => c <= 0)
}

///|
pub fn greater(
  a : @value.Value,
  b : @value.Value,
) -> @value.Value raise OpFailure {
  ordered(a, b, c => c > 0)
}

///|
pub fn greater_eq(
  a : @value.Value,
  b : @value.Value,
) -> @value.Value raise OpFailure {
  ordered(a, b, c => c >= 0)
}

///|
/// `=`: NULL if either side is NULL, else MISSING if either is MISSING, else a
/// Bool; it never fails on mixed types (partiql-tests null.ion).
pub fn equal(a : @value.Value, b : @value.Value) -> @value.Value {
  let x = a.lower() catch { _ => a }
  let y = b.lower() catch { _ => b }
  if datetime_equal(x, y) is Some(r) {
    return r
  }
  match @value.sql_equals(a, b) {
    Missing if is_null(a) || is_null(b) => Null
    other => other
  }
}

///|
fn is_null(v : @value.Value) -> Bool {
  (boxed(v) is Null) catch {
    _ => false
  }
}

///|
/// `<>`: the negation of `=`, keeping an absent result.
pub fn not_equal(a : @value.Value, b : @value.Value) -> @value.Value {
  match equal(a, b) {
    Bool(x) => Bool(!x)
    other => other
  }
}

///|
/// A binary operator by its syntax.
pub fn binary(
  op : @ast.BinaryOp,
  a : @value.Value,
  b : @value.Value,
) -> @value.Value raise OpFailure {
  match op {
    Add => add(a, b)
    Sub => sub(a, b)
    Mul => mul(a, b)
    Div => div(a, b)
    Mod => rem(a, b)
    Concat => concat(a, b)
    Eq => equal(a, b)
    Ne => not_equal(a, b)
    Lt => less(a, b)
    Le => less_eq(a, b)
    Gt => greater(a, b)
    Ge => greater_eq(a, b)
  }
}

///|
/// `x IN c` for a list, bag or row `c`: TRUE if some element equals `x`, else
/// NULL if some comparison is absent, else FALSE.
pub fn in_(x : @value.Value, c : @value.Value) -> @value.Value raise OpFailure {
  let needle = boxed(x)
  let haystack = boxed(c)
  if needle is Missing || haystack is Missing {
    return Missing
  }
  if needle is Null || haystack is Null {
    return Null
  }
  let items : Array[@value.Value] = match haystack {
    List(items) => items
    Bag(bag) => Array::from_iter(bag.items().iter())
    _ => raise TypeFailure("IN of a value that is not a collection")
  }
  let mut absent = false
  for item in items {
    match @value.sql_equals(needle, item) {
      Bool(true) => return Bool(true)
      Null | Missing => absent = true
      _ => ()
    }
  }
  if absent {
    Null
  } else {
    Bool(false)
  }
}
