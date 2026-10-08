// Relations: plan nodes that produce binding tuples as a stream (spec M4b1
// §3). Only the result of a query is collected.
//
// Errors and iterators: the producer of a core `Iter` cannot raise. A
// relation therefore evaluates eagerly what it can before it builds its
// iterator, and a step that must raise per row runs through `rows`, which
// keeps the first error in the `Ctx` and ends the iteration. `each` is the
// only consumer of a relation: after the rows, it raises the error that
// ended them. So an error never stays in the `Ctx` after `each` returns.

///|
/// An iterator over the rows that `next` produces. An error of `next` ends
/// the iteration and is kept for `each`; after an error, `next` is not
/// called again.
fn rows(ctx : Ctx, next : () -> Env? raise @plan.EvalError) -> Iter[Env] {
  Iter::new(() => {
    if ctx.failure is Some(_) {
      return None
    }
    try next() catch {
      err => {
        ctx.failure = Some(err)
        None
      }
    } noraise {
      row => row
    }
  })
}

///|
/// Calls `f` for each row of a relation, then raises the error that ended
/// the rows, if any.
fn each(
  it : Iter[Env],
  ctx : Ctx,
  f : (Env) -> Unit raise @plan.EvalError,
) -> Unit raise @plan.EvalError {
  it.each(f)
  if ctx.failure is Some(err) {
    ctx.failure = None
    raise err
  }
}

///|
/// The binding tuples of `rel`, each one inside `env`.
fn relation(
  rel : @plan.Rel,
  env : Env,
  ctx : Ctx,
) -> Iter[Env] raise @plan.EvalError {
  match rel {
    Scan(source, as_~, at~, span) =>
      scan(eval(source, env, ctx), as_, at, env, ctx, span)
    Filter(input, predicate, span) => {
      let input = relation(input, env, ctx)
      rows(ctx, () => {
        while input.next() is Some(row) {
          if holds(eval(predicate, row, ctx), ctx.mode, span) {
            return Some(row)
          }
        }
        None
      })
    }
  }
}

///|
/// One binding per element of a list or bag; `at` binds a list element's
/// position, and for a bag element MISSING in permissive mode and a
/// `TypeError` in strict mode (partiql-tests from-clause.ion,
/// `rangeOverBagWithAt`). Any other value is one binding in permissive mode
/// and a `TypeError` in strict mode (spec M4b1 §5).
fn scan(
  v : @value.Value,
  as_ : String,
  at : String?,
  env : Env,
  ctx : Ctx,
  span : @ast.Span,
) -> Iter[Env] raise @plan.EvalError {
  let bind = (x : @value.Value, position : @value.Value) => {
    let outer = match at {
      Some(name) => Frame(name, position, env)
      None => env
    }
    Frame(as_, x, outer)
  }
  match unboxed(v) {
    List(items) => items.iter().mapi((i, x) => bind(x, Int(i.to_int64())))
    Bag(_) if at is Some(_) && ctx.mode is Strict =>
      raise TypeError(message="AT over a bag, which has no positions", span~)
    Bag(b) => b.items().iter().map(x => bind(x, Missing))
    _ =>
      match ctx.mode {
        Permissive => Iter::singleton(bind(v, Missing))
        Strict =>
          raise TypeError(
            message="FROM over a value that is not a collection",
            span~,
          )
      }
  }
}

///|
/// Whether a condition keeps a row: TRUE keeps it; FALSE, NULL and MISSING
/// drop it; any other value is a type failure (spec M4b1 §5).
fn holds(
  v : @value.Value,
  mode : @plan.Mode,
  span : @ast.Span,
) -> Bool raise @plan.EvalError {
  match unboxed(v) {
    Bool(b) => b
    Null | Missing => false
    _ =>
      typed(mode, span, () => raise TypeFailure("a condition must be a boolean"))
      is Bool(true)
  }
}

///|
/// A query block: the projection of each binding tuple, as a bag. `SELECT
/// VALUE` keeps a MISSING value (partiql-tests spec-tests.ion, "bag element
/// evaluates to MISSING").
fn select(
  rel : @plan.Rel,
  projection : @plan.Projection,
  distinct : Bool,
  env : Env,
  ctx : Ctx,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  if distinct {
    raise Unsupported(message="SELECT DISTINCT is not supported yet", span~)
  }
  let out = []
  each(relation(rel, env, ctx), ctx, row => {
    match projection {
      Value(e) => out.push(eval(e, row, ctx))
    }
  })
  Bag(@value.Bag::new(out))
}
