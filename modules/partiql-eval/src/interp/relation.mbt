// Relations: plan nodes that produce binding tuples as a stream (spec M4b1
// §3). Only the result of a query is collected.
//
// Errors and iterators: the producer of a core `Iter` cannot raise. A
// relation therefore evaluates eagerly what it can before it builds its
// iterator, and a step that must raise per row runs through `rows`, which
// keeps the error in the `Ctx` and ends the iteration. For a relation's
// iterator, "no more rows" and "failed" both look like `None` to `next()`.
//
// The rule: never call `next()` on a relation's iterator. Read it with
// `pull` (row by row) or `each` (to the end); both raise the error that
// ended the rows and clear it from the `Ctx`. So an error never outlives the
// read that met it, and a consumer never mistakes a failure for the end.

///|
/// An iterator over the rows that `next` produces. An error of `next` ends
/// the iteration and is kept in `ctx` for `pull` or `each`; the first error
/// kept wins. After the end or an error, `next` is not called again.
fn rows(ctx : Ctx, next : () -> Env? raise @plan.EvalError) -> Iter[Env] {
  let mut ended = false
  Iter::new(() => {
    if ended {
      return None
    }
    let row = try next() catch {
      err => {
        if ctx.failure is None {
          ctx.failure = Some(err)
        }
        None
      }
    } noraise {
      row => row
    }
    if row is None {
      ended = true
    }
    row
  })
}

///|
/// The next row of a relation, or `None` at its end. Raises the error that
/// ended the rows, and clears it from `ctx`.
fn pull(it : Iter[Env], ctx : Ctx) -> Env? raise @plan.EvalError {
  match it.next() {
    Some(row) => Some(row)
    None =>
      match ctx.failure {
        Some(err) => {
          ctx.failure = None
          raise err
        }
        None => None
      }
  }
}

///|
/// Calls `f` for each row of a relation, to the end. Raises the error that
/// ended the rows, and clears it from `ctx`.
fn each(
  it : Iter[Env],
  ctx : Ctx,
  f : (Env) -> Unit raise @plan.EvalError,
) -> Unit raise @plan.EvalError {
  while pull(it, ctx) is Some(row) {
    f(row)
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
    Unpivot(source, as_~, at~, span) =>
      unpivot(eval(source, env, ctx), as_, at, env, ctx, span)
    Join(_, _, _, on=_, _) => join(rel, env, ctx)
    Filter(input, predicate, span) => {
      let input = relation(input, env, ctx)
      rows(ctx, () => {
        while pull(input, ctx) is Some(row) {
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
/// One binding per attribute of a tuple, `at` binding its name. Any other
/// value is the tuple `{'_1': value}` in permissive mode and a `TypeError` in
/// strict mode (spec section 5.2; the corpus has no case for it).
fn unpivot(
  v : @value.Value,
  as_ : String,
  at : String?,
  env : Env,
  ctx : Ctx,
  span : @ast.Span,
) -> Iter[Env] raise @plan.EvalError {
  let bind = (name : String, x : @value.Value) => {
    let outer = match at {
      Some(at) => Frame(at, String(name), env)
      None => env
    }
    Frame(as_, x, outer)
  }
  match unboxed(v) {
    Tuple(t) => t.fields().iter().map(f => bind(f.0, f.1))
    _ =>
      match ctx.mode {
        Permissive => Iter::singleton(bind("_1", v))
        Strict =>
          raise TypeError(
            message="UNPIVOT over a value that is not a tuple",
            span~,
          )
      }
  }
}

///|
/// The variables a relation binds, in no particular order.
fn binds(rel : @plan.Rel) -> Array[String] {
  match rel {
    Scan(_, as_~, at~, _) | Unpivot(_, as_~, at~, _) =>
      match at {
        Some(at) => [at, as_]
        None => [as_]
      }
    Filter(input, _, _) => binds(input)
    Join(_, l, r, on=_, _) => binds(l) + binds(r)
  }
}

///|
/// `env` with each of `names` bound to NULL: the padding of an outer join.
fn padded(env : Env, names : Array[String]) -> Env {
  names.fold(init=env, (acc, name) => Frame(name, Null, acc))
}

///|
/// `env` with the variables `names` of `row` on top.
fn with_bindings(env : Env, row : Env, names : Array[String]) -> Env {
  names.fold(init=env, (acc, name) => {
    match row.find(name) {
      Some(x) => Frame(name, x, acc)
      None => acc
    }
  })
}

///|
/// A join. Cross, inner and left joins read the left side row by row and, for
/// each left row, the right side inside that row (so the right side may use
/// the left variables). A right join cannot do that, as its unmatched rows
/// are on the right: it reads the right side once, outside the left rows, and
/// keeps those rows in an array with a flag per row for "matched" (the only
/// materialization of a join). A chain of joins on the left is unrolled by a
/// loop, not by recursion per join.
fn join(
  rel : @plan.Rel,
  env : Env,
  ctx : Ctx,
) -> Iter[Env] raise @plan.EvalError {
  let steps = []
  let mut leaf = rel
  while leaf is Join(kind, l, r, on~, span) {
    steps.push((kind, r, on, span))
    leaf = l
  }
  let mut it = relation(leaf, env, ctx)
  // The variables of the left side grow with each step.
  let left_names = binds(leaf)
  for step in steps.rev_iter() {
    let (kind, right, on, span) = step
    it = match kind {
      Right => right_join(it, right, on, span, env, ctx, left_names.copy())
      _ => left_to_right(kind, it, right, on, span, ctx)
    }
    left_names.append(binds(right))
  }
  it
}

///|
fn matches(
  on : @plan.Expr?,
  row : Env,
  ctx : Ctx,
  span : @ast.Span,
) -> Bool raise @plan.EvalError {
  match on {
    Some(e) => holds(eval(e, row, ctx), ctx.mode, span)
    None => true
  }
}

///|
fn left_to_right(
  kind : @plan.JoinKind,
  left : Iter[Env],
  right : @plan.Rel,
  on : @plan.Expr?,
  span : @ast.Span,
  ctx : Ctx,
) -> Iter[Env] {
  let right_names = binds(right)
  let mut current : (Env, Iter[Env])? = None
  let mut matched = false
  rows(ctx, () => {
    while true {
      match current {
        None =>
          match pull(left, ctx) {
            None => return None
            Some(l) => {
              current = Some((l, relation(right, l, ctx)))
              matched = false
            }
          }
        Some((l, rs)) =>
          // Read the right row at once: its failure belongs to this read.
          match pull(rs, ctx) {
            Some(r) =>
              if matches(on, r, ctx, span) {
                matched = true
                return Some(r)
              }
            None => {
              current = None
              if kind is Left && !matched {
                return Some(padded(l, right_names))
              }
            }
          }
      }
    }
    None
  })
}

///|
fn right_join(
  left : Iter[Env],
  right : @plan.Rel,
  on : @plan.Expr?,
  span : @ast.Span,
  env : Env,
  ctx : Ctx,
  left_names : Array[String],
) -> Iter[Env] {
  let right_names = binds(right)
  let right_rows = []
  let matched = []
  let mut loaded = false
  // Phase one: pairs, in the order of the left rows. Phase two: the right
  // rows that no left row matched, with NULL for the left variables.
  let mut current : Env? = None
  let mut index = 0
  let mut unmatched = 0
  rows(ctx, () => {
    if !loaded {
      each(relation(right, env, ctx), ctx, r => {
        right_rows.push(r)
        matched.push(false)
      })
      loaded = true
    }
    while true {
      match current {
        None if index >= 0 =>
          match pull(left, ctx) {
            Some(l) => {
              current = Some(l)
              index = 0
            }
            None => index = -1
          }
        Some(l) =>
          if index < right_rows.length() {
            let j = index
            index += 1
            let row = with_bindings(l, right_rows[j], right_names)
            if matches(on, row, ctx, span) {
              matched[j] = true
              return Some(row)
            }
          } else {
            current = None
          }
        None =>
          if unmatched < right_rows.length() {
            let j = unmatched
            unmatched += 1
            if !matched[j] {
              return Some(
                with_bindings(
                  padded(env, left_names),
                  right_rows[j],
                  right_names,
                ),
              )
            }
          } else {
            return None
          }
      }
    }
    None
  })
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
