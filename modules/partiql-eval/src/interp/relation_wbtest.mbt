///|
fn at(start : Int32) -> @ast.Span {
  { start, end: start + 1, }
}

///|
fn fail_at(start : Int32) -> @plan.EvalError {
  DataError(message="failure \{start}", span=at(start))
}

///|
/// The error that `f` raises, if any.
fn raised(f : () -> Unit raise @plan.EvalError) -> @plan.EvalError? {
  try f() catch {
    err => Some(err)
  } noraise {
    _ => None
  }
}

///|
/// The number of rows of `rel`, read to the end.
fn count(rel : @plan.Rel, ctx : Ctx) -> Int32 raise @plan.EvalError {
  let mut n = 0
  each(relation(rel, Top, ctx), ctx, _ => n = n + 1)
  n
}

///|
/// `x` over `[1, 2]`.
let numbers : @plan.Rel = Scan(
  ListOf(
    [
      Const(@value.Value::from_int(1), at(0)),
      Const(@value.Value::from_int(2), at(0)),
    ],
    at(0),
  ),
  as_="x",
  at=None,
  at(0),
)

///|
/// A relation whose second row fails in strict mode: `x + 'a'` at 7.
let failing : @plan.Rel = Filter(
  numbers,
  Binary(
    Add,
    Local("x", at(5)),
    Const(@value.Value::from_string("a"), at(6)),
    at(7),
  ),
  at(8),
)

///|
test "a failing input read through Filter raises the input's error" {
  let ctx = Ctx([], mode=Strict)
  let outer : @plan.Rel = Filter(
    failing,
    Const(@value.Value::from_bool(true), at(9)),
    at(10),
  )
  let it = relation(outer, Top, ctx)
  @expect.expect_all(soft => {
    soft
    .expect(raised(() => ignore(pull(it, ctx))))
    .to_satisfy(e => e is Some(TypeError(span~, ..)) && span == at(7))
    soft.expect(ctx.failure).to_equal(None)
  })
}

///|
test "after an error, the same Ctx reads a later relation" {
  let ctx = Ctx([], mode=Strict)
  @expect.expect_all(soft => {
    soft
    .expect(raised(() => ignore(pull(relation(failing, Top, ctx), ctx))))
    .to_satisfy(e => e is Some(TypeError(..)))
    soft.expect(count(numbers, ctx)).to_equal(2)
    soft
    .expect(raised(() => ignore(count(failing, ctx))))
    .to_satisfy(e => e is Some(TypeError(..)))
    soft.expect(count(numbers, ctx)).to_equal(2)
  })
}

///|
test "of two errors in sequence, the first is reported" {
  let ctx = Ctx([], mode=Strict)
  let first = rows(ctx, () => raise fail_at(1))
  // A consumer that, like a join, goes on after its input ends.
  let second = rows(ctx, () => {
    ignore(first.next())
    raise fail_at(2)
  })
  @expect.expect(raised(() => each(second, ctx, _ => ()))).to_equal(
    Some(fail_at(1)),
  )
}
