// Set operations (RFC 0007; spec M4b2, plan rulings 4-7): UNION, INTERSECT
// and EXCEPT, each with ALL or DISTINCT, as the PartiQL bag operator (OUTER)
// or with SQL rules (relations matched by position or by CORRESPONDING).

///|
/// A multiset of values under grouping equivalence (`eqg`, the test of
/// DISTINCT and GROUP BY: `1` and `1.0` are one value, NULLs are one value).
/// Each value goes to a bucket of its `group_key`; only the values of one
/// bucket are compared, so the cost is linear unless many values share a
/// key.
priv struct Counter {
  buckets : Map[String, Array[(@value.Value, Ref[Int32])]]
}

///|
fn Counter::Counter() -> Counter {
  { buckets: Map([]), }
}

///|
/// The multiset of `values`.
fn Counter::of(values : Array[@value.Value]) -> Counter {
  let counter = Counter()
  for v in values {
    ignore(counter.add(v))
  }
  counter
}

///|
/// The count of the entry of `v`, if `v` has one.
fn Counter::entry(self : Counter, v : @value.Value) -> Ref[Int32]? {
  guard self.buckets.get(@value.group_key(v)) is Some(bucket) else {
    return None
  }
  for entry in bucket {
    if @value.eqg(entry.0, v) {
      return Some(entry.1)
    }
  }
  None
}

///|
/// Adds one `v`; whether it is the first of its value.
fn Counter::add(self : Counter, v : @value.Value) -> Bool {
  match self.entry(v) {
    Some(count) => {
      count.val += 1
      false
    }
    None => {
      self.buckets.get_or_init(@value.group_key(v), () => []).push((v, Ref(1)))
      true
    }
  }
}

///|
/// How many times `v` is in the multiset.
fn Counter::count(self : Counter, v : @value.Value) -> Int32 {
  match self.entry(v) {
    Some(count) => count.val
    None => 0
  }
}

///|
/// Removes one `v`; whether there was one to remove.
fn Counter::take(self : Counter, v : @value.Value) -> Bool {
  match self.entry(v) {
    Some(count) if count.val > 0 => {
      count.val -= 1
      true
    }
    _ => false
  }
}

///|
/// The first of each value of `values`, in order.
fn dedupe(values : Array[@value.Value]) -> Array[@value.Value] {
  let seen = Counter()
  values.filter(v => seen.add(v))
}

///|
/// A chain of set operations. The chain is walked down its left spine in a
/// loop, so a long chain takes no recursion per link: the innermost left
/// operand runs first, then each step combines the result so far with its
/// right operand. The result is a bag.
fn set_op(
  e : @plan.Expr,
  env : Env,
  ctx : Ctx,
) -> @value.Value raise @plan.EvalError {
  let steps = []
  let mut leaf = e
  while leaf is SetOp(kind, all~, outer~, corresponding~, l, r, span) {
    steps.push((kind, all, outer, corresponding, r, span))
    leaf = l
  }
  let mut acc = eval(leaf, env, ctx)
  let mut acc_span = leaf.span()
  for step in steps.rev_iter() {
    let (kind, all, outer, corresponding, right_expr, span) = step
    let right = eval(right_expr, env, ctx)
    let (left_items, right_items) = if outer {
      let l = outer_items(acc, ctx, acc_span)
      let r = outer_items(right, ctx, right_expr.span())
      match corresponding {
        Some(c) => {
          let names = outer_names(c, l, r)
          (outer_projected(l, names), outer_projected(r, names))
        }
        None => (l, r)
      }
    } else {
      conform(
        relation_items(acc, acc_span),
        relation_items(right, right_expr.span()),
        corresponding,
        span,
      )
    }
    acc = @value.Value::from_bag(
      @value.Bag(combine(kind, all, left_items, right_items)),
    )
    acc_span = span
  }
  acc
}

///|
/// The multiset operation `kind` (plan ruling 6). The result keeps the left
/// elements, then the right ones; INTERSECT and EXCEPT without ALL keep each
/// distinct left value once.
fn combine(
  kind : @ast.SetOpKind,
  all : Bool,
  left : Array[@value.Value],
  right : Array[@value.Value],
) -> Array[@value.Value] {
  match kind {
    Union => {
      let both = left + right
      if all {
        both
      } else {
        dedupe(both)
      }
    }
    Intersect => {
      let counts = Counter::of(right)
      if all {
        left.filter(v => counts.take(v))
      } else {
        dedupe(left).filter(v => counts.count(v) > 0)
      }
    }
    Except => {
      let counts = Counter::of(right)
      if all {
        left.filter(v => !counts.take(v))
      } else {
        dedupe(left).filter(v => counts.count(v) == 0)
      }
    }
  }
}

///|
/// The elements of an operand of an OUTER operation (plan ruling 5): the
/// items of a list or a bag; none for NULL and MISSING, in both modes; any
/// other value is a one-element bag in permissive mode and a `TypeError` in
/// strict mode.
fn outer_items(
  v : @value.Value,
  ctx : Ctx,
  span : @ast.Span,
) -> Array[@value.Value] raise @plan.EvalError {
  match unboxed(v) {
    List(items) => items
    Bag(b) => b.items().to_owned()
    Null | Missing => []
    other =>
      match ctx.mode {
        Permissive => [other]
        Strict =>
          raise TypeError(
            message="an operand of an OUTER set operation must be a collection",
            span~,
          )
      }
  }
}

///|
/// The tuples of an operand of a SQL set operation (plan ruling 4): a list
/// or a bag whose elements are all tuples, else a `DataError`.
fn relation_items(
  v : @value.Value,
  span : @ast.Span,
) -> Array[@value.Tuple] raise @plan.EvalError {
  let items = match unboxed(v) {
    List(items) => items[:]
    Bag(b) => b.items()
    _ =>
      raise DataError(
        message="an operand of a set operation must be a collection of tuples; use OUTER for other values",
        span~,
      )
  }
  let tuples = []
  for item in items {
    guard unboxed(item) is Tuple(t) else {
      raise DataError(
        message="an operand of a set operation must be a collection of tuples; use OUTER for other values",
        span~,
      )
    }
    tuples.push(t)
  }
  tuples
}

///|
/// A name of CORRESPONDING and how it matches an attribute: a regular
/// identifier ignores case, a delimited one and a name taken from a tuple do
/// not.
priv struct Column {
  name : String
  delimited : Bool
}

///|
/// The value of the first attribute of `t` that `column` names.
fn column_of(t : @value.Tuple, column : Column) -> @value.Value? {
  let wanted = if column.delimited {
    column.name
  } else {
    column.name.to_lower()
  }
  for field in t.fields() {
    let key = if column.delimited { field.0 } else { field.0.to_lower() }
    if key == wanted {
      return Some(field.1)
    }
  }
  None
}

///|
/// The columns of CORRESPONDING (plan ruling 7): the BY names in order, or
/// the names that the first left and the first right tuple share, in left
/// order. With a tuple on one side only, the names of that tuple: an empty
/// side does not change the other side.
fn corresponding_columns(
  c : @ast.Corresponding,
  first_left : @value.Tuple?,
  first_right : @value.Tuple?,
) -> Array[Column] {
  match c {
    By(ids) => ids.map(id => { name: id.text, delimited: id.delimited, })
    All =>
      match (first_left, first_right) {
        (Some(l), Some(r)) => shared_columns(l, r)
        (Some(t), None) | (None, Some(t)) => shared_columns(t, t)
        (None, None) => []
      }
  }
}

///|
/// The attribute names of `l` that `r` has too, each once, in `l` order.
/// Names from tuples match exactly.
fn shared_columns(l : @value.Tuple, r : @value.Tuple) -> Array[Column] {
  let shared : Array[Column] = []
  for field in l.fields() {
    let column = { name: field.0, delimited: true, }
    if column_of(r, column) is Some(_) &&
      !shared.iter().any(seen => seen.name == field.0) {
      shared.push(column)
    }
  }
  shared
}

///|
/// The columns of CORRESPONDING for an OUTER operation, from the first tuple
/// of each side.
fn outer_names(
  c : @ast.Corresponding,
  left : Array[@value.Value],
  right : Array[@value.Value],
) -> Array[Column] {
  let first_tuple = (items : Array[@value.Value]) => {
    for item in items {
      if unboxed(item) is Tuple(t) {
        break Some(t)
      }
    } nobreak {
      None
    }
  }
  corresponding_columns(c, first_tuple(left), first_tuple(right))
}

///|
/// The elements of an OUTER operand under CORRESPONDING (plan ruling 7): a
/// tuple keeps the columns it has, a value that is not a tuple is unchanged.
fn outer_projected(
  items : Array[@value.Value],
  columns : Array[Column],
) -> Array[@value.Value] {
  items.map(item => {
    guard unboxed(item) is Tuple(t) else { return item }
    let fields = []
    for column in columns {
      if column_of(t, column) is Some(v) {
        fields.push((column.name, v))
      }
    }
    @value.Value::from_tuple(@value.Tuple(fields))
  })
}

///|
/// The two operands of a SQL set operation as rows with the same names
/// (plan rulings 4 and 7). With CORRESPONDING, each tuple is cut to the
/// corresponding columns, and a tuple without one of them is a `DataError`,
/// as is plain CORRESPONDING when both sides have tuples but no common name.
/// Otherwise the columns match by position: every tuple takes the names of
/// the first left tuple (of the first right one if the left is empty), and
/// a tuple with another number of attributes is a `DataError`. Last, the
/// values of each column must be comparable: if both sides have values in a
/// column that is not NULL or MISSING, they must share a kind.
fn conform(
  left : Array[@value.Tuple],
  right : Array[@value.Tuple],
  corresponding : @ast.Corresponding?,
  span : @ast.Span,
) -> (Array[@value.Value], Array[@value.Value]) raise @plan.EvalError {
  let (names, l, r) = match corresponding {
    Some(c) => {
      let columns = corresponding_columns(c, left.get(0), right.get(0))
      // Plain CORRESPONDING over two sides that share no name would make
      // every row the empty tuple.
      if c is All && columns.is_empty() && !left.is_empty() && !right.is_empty() {
        raise DataError(message="CORRESPONDING finds no common column", span~)
      }
      (
        columns.map(column => column.name),
        corresponding_rows(left, columns, span),
        corresponding_rows(right, columns, span),
      )
    }
    None => {
      let names = match (left.get(0), right.get(0)) {
        (Some(t), _) | (None, Some(t)) => t.fields().map(field => field.0)
        (None, None) => []
      }
      (
        names,
        positional_rows(left, names.length(), span),
        positional_rows(right, names.length(), span),
      )
    }
  }
  check_columns(names.length(), l, r, span)
  let tuple_of = (values : Array[@value.Value]) => {
    @value.Value::from_tuple(
      @value.Tuple(Array::makei(names.length(), i => (names[i], values[i]))),
    )
  }
  (l.map(tuple_of), r.map(tuple_of))
}

///|
/// The values of the CORRESPONDING columns of each tuple; a tuple without
/// one of them is a `DataError`.
fn corresponding_rows(
  tuples : Array[@value.Tuple],
  columns : Array[Column],
  span : @ast.Span,
) -> Array[Array[@value.Value]] raise @plan.EvalError {
  let out = []
  for t in tuples {
    let values = []
    for column in columns {
      guard column_of(t, column) is Some(v) else {
        raise DataError(
          message="a tuple of a set operation has no attribute \{column.name}",
          span~,
        )
      }
      values.push(v)
    }
    out.push(values)
  }
  out
}

///|
/// The attribute values of each tuple, by position; a tuple that does not
/// have `degree` attributes is a `DataError`.
fn positional_rows(
  tuples : Array[@value.Tuple],
  degree : Int32,
  span : @ast.Span,
) -> Array[Array[@value.Value]] raise @plan.EvalError {
  let out = []
  for t in tuples {
    if t.length() != degree {
      raise DataError(
        message="the operands of a set operation must have the same number of columns; use OUTER or CORRESPONDING",
        span~,
      )
    }
    out.push(t.fields().map(field => field.1))
  }
  out
}

///|
/// A `DataError` if a column has values on both sides that are not NULL or
/// MISSING and share no kind (RFC 0007 Example 6: `1` and `'A'`).
fn check_columns(
  degree : Int32,
  left : Array[Array[@value.Value]],
  right : Array[Array[@value.Value]],
  span : @ast.Span,
) -> Unit raise @plan.EvalError {
  for i in 0..<degree {
    let l = kinds_of(left, i)
    let r = kinds_of(right, i)
    if l != 0 && r != 0 && (l & r) == 0 {
      raise DataError(
        message="column \{i + 1} of a set operation has values of different kinds",
        span~,
      )
    }
  }
}

///|
/// The kinds of the values of column `i`, one bit per `kind_class`.
fn kinds_of(rows : Array[Array[@value.Value]], i : Int32) -> Int32 {
  let mut mask = 0
  for row in rows {
    if kind_class(row[i]) is Some(k) {
      mask = mask | (1 << k)
    }
  }
  mask
}

///|
/// The kind of a value for the column check of a SQL set operation: `None`
/// for NULL and MISSING; one class each for bool, number (int, decimal,
/// float), text, date, time, timestamp, interval, lob, list and
/// s-expression, tuple, bag, map and graph.
fn kind_class(v : @value.Value) -> Int32? {
  match unboxed(v) {
    Null | Missing => None
    Bool(_) => Some(0)
    Int(_) | BigInt(_) | Float(_) | Decimal(_) => Some(1)
    // An Ion value that stays boxed is a symbol without text.
    String(_) | Ion(_) => Some(2)
    Date(_) => Some(3)
    Time(_) => Some(4)
    Timestamp(_) => Some(5)
    IntervalYM(_) | IntervalDT(_) => Some(6)
    Clob(_) | Blob(_) => Some(7)
    List(_) => Some(8)
    Tuple(_) => Some(9)
    Bag(_) => Some(10)
    Map(_) => Some(11)
    Graph(_) => Some(12)
  }
}
