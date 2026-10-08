// The run-time depth of a plan. The interpreter recurses on the plan, and a
// join wraps iterators around iterators, so a plan that is too deep would
// overflow the stack when it runs. Lowering accepts a plan only if every
// path through it, from the root to the deepest part that runs, costs at
// most `max_depth` levels.
//
// The cost of each part is what it puts on the interpreter's stack, in
// levels of one scalar `eval`. A level of each part below was measured on
// wasm, wasm-gc and js in a new process (where the stack is smallest), with
// a chain of `IS NOT NULL` under it:
//
// - A scalar expression: 1 per level (its operands run in a nested `eval`).
//   A chain of binary operators, AND and OR runs in a loop: its operands
//   are all one level down.
// - A literal: 1 per level of its value (operations on a value recurse on
//   it).
// - A query block: 1, its FROM, WHERE and joins 1 below it, its projection 2
//   below it. Measured: about 1.1 per nested query block.
// - A FROM source: 1, its expression 1 below it. Measured with a query in a
//   FROM source: about 1.6 per query block and source.
// - A WHERE: 1, its input and its condition 1 below it.
// - A join: one wrapper per right join, and one per run of cross, inner and
//   left joins between them (`chain` runs a run as one flat loop). Each
//   wrapper is 1; the wrappers nest in the order of the joins, the last one
//   outermost. A right side and an ON run inside their wrapper, 1 below it;
//   the first source of the join runs below all the wrappers. Measured: about
//   0.37 per right join, and about 2.5 to 2.75 for a query block in an ON.
//
// Each charge is at least what was measured, so a plan within `max_depth`
// uses no more stack than a scalar expression `max_depth` levels deep,
// which runs on every target.

///|
/// A part of a plan and the level at which it runs: the number of levels on
/// the stack, itself included.
priv enum Pending {
  ExprAt(@plan.Expr, Int)
  RelAt(@plan.Rel, Int)
}

///|
/// The nesting depth of a value (a scalar is 1), counted in a loop.
fn value_depth(v : @value.Value) -> Int {
  let mut deepest = 0
  let pending = [(v, 1)]
  while pending.pop() is Some((x, d)) {
    deepest = deepest.max(d)
    match x {
      List(items) =>
        for item in items {
          pending.push((item, d + 1))
        }
      Bag(b) =>
        for item in b.items() {
          pending.push((item, d + 1))
        }
      Tuple(t) =>
        for field in t.fields() {
          pending.push((field.1, d + 1))
        }
      Map(m) =>
        for entry in m.entries() {
          pending.push((entry.0, d + 1))
          pending.push((entry.1, d + 1))
        }
      Ion(i) => deepest = deepest.max(d + ion_depth(i) - 1)
      _ => ()
    }
  }
  deepest
}

///|
/// Pushes the operands of a scalar expression at `level`, one level down.
/// A chain of binary operators, AND and OR is walked down its left spine:
/// it runs in a loop, so all its operands are one level down.
fn push_operands(e : @plan.Expr, level : Int, pending : Array[Pending]) -> Unit {
  let below = level + 1
  let push = (x : @plan.Expr) => pending.push(ExprAt(x, below))
  match e {
    Const(_, _)
    | Global(_, delimited=_, _)
    | Local(_, _)
    | GlobalOrLocal(_, variable=_, delimited=_, _) => ()
    ListOf(items, _) | BagOf(items, _) | Coalesce(items, _) => items.each(push)
    TupleOf(pairs, _) | MapOf(pairs, _) =>
      for pair in pairs {
        push(pair.0)
        push(pair.1)
      }
    Path(base, steps, _) => {
      push(base)
      for step in steps {
        if step is Index(x) {
          push(x)
        }
      }
    }
    IsNull(x, negated=_, _)
    | IsMissing(x, negated=_, _)
    | Unary(_, x, _)
    | Not(x, _)
    | BoolTest(x, _, negated=_, _)
    | IsType(x, _, negated=_, _) => push(x)
    Binary(_, _, _, _) | And(_, _, _) | Or(_, _, _) => {
      let mut leaf = e
      while true {
        match leaf {
          Binary(_, l, r, _) | And(l, r, _) | Or(l, r, _) => {
            push(r)
            leaf = l
          }
          _ => break
        }
      }
      push(leaf)
    }
    Like(x, pattern~, escape~, negated=_, _) => {
      push(x)
      push(pattern)
      if escape is Some(x) {
        push(x)
      }
    }
    Between(x, low~, high~, negated=_, _) => {
      push(x)
      push(low)
      push(high)
    }
    In(x, c, negated=_, _) | NullIf(x, c, _) => {
      push(x)
      push(c)
    }
    Case(operand~, branches~, default~, _) => {
      if operand is Some(x) {
        push(x)
      }
      for branch in branches {
        push(branch.0)
        push(branch.1)
      }
      if default is Some(x) {
        push(x)
      }
    }
    Select(rel, projection, distinct=_, _) => {
      pending.push(RelAt(rel, below))
      match projection {
        Value(x) => pending.push(ExprAt(x, below + 1))
      }
    }
  }
}

///|
/// Pushes the parts of a join at `level`: its wrappers, one per right join
/// and one per run of other joins, nest from the last join (at `level`) to
/// the first; a right side and an ON run one level below their wrapper, the
/// first source below all the wrappers.
fn push_join(rel : @plan.Rel, level : Int, pending : Array[Pending]) -> Unit {
  let steps = []
  let mut leaf = rel
  while leaf is Join(kind, l, r, on~, _) {
    steps.push((kind, r, on))
    leaf = l
  }
  steps.rev_in_place()
  // The wrapper of each step, counted from the innermost.
  let wrappers = []
  let mut count = 0
  let mut in_run = false
  for step in steps {
    if step.0 is Right {
      count += 1
      in_run = false
    } else if !in_run {
      count += 1
      in_run = true
    }
    wrappers.push(count)
  }
  for i, step in steps {
    let below = level + count - wrappers[i] + 1
    pending.push(RelAt(step.1, below))
    if step.2 is Some(on) {
      pending.push(ExprAt(on, below))
    }
  }
  pending.push(RelAt(leaf, level + count))
}

///|
/// `plan` if it runs within `max_depth` levels; otherwise a `DataError` at
/// the part that goes deeper. A loop with a stack of pending parts, so a
/// long plan takes no recursion here.
fn within_depth(plan : @plan.Expr) -> @plan.Expr raise @plan.EvalError {
  let pending = [ExprAt(plan, 1)]
  while pending.pop() is Some(part) {
    let (level, span) = match part {
      ExprAt(Const(v, span), level) => (level + value_depth(v) - 1, span)
      ExprAt(e, level) => (level, e.span())
      RelAt(r, level) => (level, r.span())
    }
    if level > max_depth {
      raise DataError(message="expression is too deep", span~)
    }
    match part {
      ExprAt(e, level) => push_operands(e, level, pending)
      RelAt(
        Scan(source, as_=_, at=_, _)
        | Unpivot(source, as_=_, at=_, _),
        level
      ) => pending.push(ExprAt(source, level + 1))
      RelAt(Filter(input, predicate, _), level) => {
        pending.push(RelAt(input, level + 1))
        pending.push(ExprAt(predicate, level + 1))
      }
      RelAt(Join(_, _, _, on=_, _) as rel, level) =>
        push_join(rel, level, pending)
    }
  }
  plan
}
