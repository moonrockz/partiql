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
    Let(input, bindings, _) => {
      let input = relation(input, env, ctx)
      rows(ctx, () => {
        match pull(input, ctx) {
          Some(row) => {
            let mut bound = row
            for binding in bindings {
              bound = Frame(binding.0, eval(binding.1, bound, ctx), bound)
            }
            Some(bound)
          }
          None => None
        }
      })
    }
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
/// One binding per attribute of a tuple, `at` binding its name, or per entry
/// of a map, `at` binding its key (partiql-tests map.ion, "UNPIVOT"). MISSING
/// has no bindings in permissive mode (path.ion, `unpivotMissing`). Any other
/// value is the tuple `{'_1': value}` in permissive mode. In strict mode a
/// value that is not a tuple or a map is a `TypeError` (spec section 5.2).
fn unpivot(
  v : @value.Value,
  as_ : String,
  at : String?,
  env : Env,
  ctx : Ctx,
  span : @ast.Span,
) -> Iter[Env] raise @plan.EvalError {
  let bind = (name : @value.Value, x : @value.Value) => {
    let outer = match at {
      Some(at) => Frame(at, name, env)
      None => env
    }
    Frame(as_, x, outer)
  }
  match unboxed(v) {
    Tuple(t) => t.fields().iter().map(f => bind(String(f.0), f.1))
    Map(m) => m.entries().iter().map(e => bind(e.0, e.1))
    _ =>
      match ctx.mode {
        Strict =>
          raise TypeError(
            message="UNPIVOT over a value that is not a tuple or a map",
            span~,
          )
        Permissive =>
          match unboxed(v) {
            Missing => Iter::empty()
            _ => Iter::singleton(bind(String("_1"), v))
          }
      }
  }
}

///|
/// The variables a relation binds: those of the left side of a join before
/// those of the right. A loop with a stack of pending relations, so a long
/// chain of joins takes no recursion.
fn binds(rel : @plan.Rel) -> Array[String] {
  let names = []
  let pending = [rel]
  while pending.pop() is Some(r) {
    match r {
      Scan(_, as_~, at~, _) | Unpivot(_, as_~, at~, _) => {
        if at is Some(at) {
          names.push(at)
        }
        names.push(as_)
      }
      Filter(input, _, _) | Let(input, _, _) => pending.push(input)
      Join(_, l, r, on=_, _) => {
        pending.push(r)
        pending.push(l)
      }
    }
  }
  names
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
/// materialization of a join).
///
/// The joins of a chain on the left run as one flat nested loop (`chain`),
/// so one pull takes no recursion per join. Only a right join, which wraps
/// the rows before it, nests; lowering bounds those.
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
  let run = []
  for step in steps.rev_iter() {
    let (kind, right, on, span) = step
    if kind is Right {
      if !run.is_empty() {
        it = chain(it, run.copy(), ctx)
        run.clear()
      }
      it = right_join(it, right, on, span, env, ctx, left_names.copy())
    } else {
      run.push((kind, right, on, span))
    }
    left_names.append(binds(right))
  }
  if run.is_empty() {
    it
  } else {
    chain(it, run, ctx)
  }
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
/// Cross, inner and left joins in a row, as one nested loop with one level
/// per join. Level `k` holds the row it reads from (`lefts[k]`), the iterator
/// of its right side inside that row, and whether a right row matched (for
/// the padding of a left join). Like an odometer, the deepest level advances
/// first; a level that runs out hands control back to the one before it. The
/// right row of a level is read with `pull` at once, so its failure ends the
/// rows before the next left row is read, and a left join does not pad after
/// a failure.
fn chain(
  base : Iter[Env],
  steps : Array[(@plan.JoinKind, @plan.Rel, @plan.Expr?, @ast.Span)],
  ctx : Ctx,
) -> Iter[Env] {
  let n = steps.length()
  let names = steps.map(step => binds(step.1))
  let lefts : Array[Env] = Array::make(n, Top)
  let iters : Array[Iter[Env]?] = Array::make(n, None)
  let matched = Array::make(n, false)
  let mut k = 0
  rows(ctx, () => {
    while true {
      let (kind, right, on, span) = steps[k]
      match iters[k] {
        None =>
          if k > 0 {
            k -= 1
          } else {
            match pull(base, ctx) {
              None => return None
              Some(l) => {
                lefts[0] = l
                iters[0] = Some(relation(right, l, ctx))
                matched[0] = false
              }
            }
          }
        Some(rs) => {
          let out = match pull(rs, ctx) {
            Some(r) =>
              if matches(on, r, ctx, span) {
                matched[k] = true
                Some(r)
              } else {
                None
              }
            None => {
              iters[k] = None
              if kind is Left && !matched[k] {
                Some(padded(lefts[k], names[k]))
              } else {
                None
              }
            }
          }
          if out is Some(o) {
            if k == n - 1 {
              return Some(o)
            }
            k += 1
            lefts[k] = o
            iters[k] = Some(relation(steps[k].1, o, ctx))
            matched[k] = false
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
) -> @value.Value raise @plan.EvalError {
  let out = []
  each(relation(rel, env, ctx), ctx, row => {
    out.push(project(projection, row, ctx))
  })
  Bag(@value.Bag::new(if distinct { dedupe(out) } else { out }))
}

///|
/// The projection of one binding tuple.
fn project(
  projection : @plan.Projection,
  row : Env,
  ctx : Ctx,
) -> @value.Value raise @plan.EvalError {
  match projection {
    Value(e) => eval(e, row, ctx)
    Star(names) => {
      let fields = []
      for i, name in names {
        if row.find(name) is Some(v) {
          add_fields(fields, v, i)
        }
      }
      Tuple(@value.Tuple::new(fields))
    }
    Items(items) => {
      let fields = []
      for i, item in items {
        match item {
          Named(name, e) => {
            let v = eval(e, row, ctx)
            // A MISSING item has no attribute in permissive mode.
            if v is Missing && ctx.mode is Strict {
              raise TypeError(message="a SELECT item is MISSING", span=e.span())
            }
            fields.push((name, v))
          }
          AllFields(e) => add_fields(fields, eval(e, row, ctx), i)
        }
      }
      Tuple(@value.Tuple::new(fields))
    }
  }
}

///|
/// Appends the attributes of `v` to `fields`. A value that is not a tuple is
/// the attribute `_` and `position` + 1, in both modes (partiql-tests
/// projection.ion, `projectOfListOfList`; spec-tests.ion, "select variable
/// star with non tuples"). It keeps its exact Ion form (projection.ion,
/// `projectOfSexp`). MISSING has no attributes.
fn add_fields(
  fields : Array[(String, @value.Value)],
  v : @value.Value,
  position : Int,
) -> Unit {
  match unboxed(v) {
    Tuple(t) => t.fields().each(f => fields.push(f))
    Missing => ()
    _ => fields.push(("_\{position + 1}", v))
  }
}

///|
/// The values of `items` without a repeat, in the order of their first
/// occurrence. Two values repeat if they are grouping equivalent (`eqg`: the
/// test of GROUP BY, so `1`, `1.0` and `1e0` are one value, NULLs are one
/// value, and bags and tuples compare as multisets). Each value goes to a
/// bucket of its `group_key`; only the values of one bucket are compared, so
/// the cost is linear unless many values share a key.
fn dedupe(items : Array[@value.Value]) -> Array[@value.Value] {
  let buckets : Map[String, Array[@value.Value]] = Map([])
  let out = []
  for v in items {
    let bucket = buckets.get_or_init(@value.group_key(v), () => [])
    if !bucket.any(seen => @value.eqg(seen, v)) {
      bucket.push(v)
      out.push(v)
    }
  }
  out
}
