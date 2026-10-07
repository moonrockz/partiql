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
/// A value lowered one level; a symbol without text stays as it is.
fn shallow(v : @value.Value) -> @value.Value {
  v.lower() catch {
    _ => v
  }
}

///|
/// Whether `xs` and `ys` are the same multiset under `same`, an equivalence
/// relation (then greedy matching is exact).
fn[T] same_multiset(
  xs : ArrayView[T],
  ys : ArrayView[T],
  same : (T, T) -> Bool,
) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  let used = Array::make(ys.length(), false)
  for x in xs {
    let mut found = false
    for j, y in ys {
      if !used[j] && same(x, y) {
        used[j] = true
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
/// The equality of two elements of a collection: the top-level `=` with the
/// datetime rule, recursively, where NULL and MISSING are equal to each
/// other (partiql-tests nary-operators.ion,
/// `equalListDifferentTypesWithNullMissingEquivalenceTrue`) and NaN equals
/// NaN. It is an equivalence relation.
fn same(a : @value.Value, b : @value.Value) -> Bool {
  let x = shallow(a)
  let y = shallow(b)
  match (x, y) {
    (Null | Missing, Null | Missing) => true
    (Null | Missing, _) | (_, Null | Missing) => false
    (List(xs), List(ys)) =>
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(p => same(p.0, p.1))
    (Bag(p), Bag(q)) => same_multiset(p.items(), q.items(), same)
    (Tuple(p), Tuple(q)) =>
      same_multiset(p.fields(), q.fields(), (f, g) => {
        f.0 == g.0 && same(f.1, g.1)
      })
    (Map(p), Map(q)) =>
      same_multiset(p.entries(), q.entries(), (e, f) => {
        same(e.0, f.0) && same(e.1, f.1)
      })
    _ =>
      match datetime_equal(x, y) {
        Some(r) => r is Bool(true)
        None => @value.eqg(x, y)
      }
  }
}

///|
/// `=`: NULL if either side is NULL, else MISSING if either is MISSING, else
/// a Bool; it never fails on mixed types (partiql-tests null.ion). A NaN
/// equals nothing. Collections compare their elements with `same`, so
/// `[DATE '2020-01-01'] = [TIMESTAMP '2020-01-01 00:00:00']` as the
/// elements do.
pub fn equal(a : @value.Value, b : @value.Value) -> @value.Value {
  let x = shallow(a)
  let y = shallow(b)
  match (x, y) {
    (Null, _) | (_, Null) => Null
    (Missing, _) | (_, Missing) => Missing
    _ => Bool(!is_nan(x) && !is_nan(y) && same(x, y))
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
/// `x IN c` for a list, bag or row `c`: TRUE if some element `=` `x`, else
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
    match equal(needle, item) {
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
