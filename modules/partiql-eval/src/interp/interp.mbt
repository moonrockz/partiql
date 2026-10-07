///|
fn lookup(
  env : Array[(String, @value.Value)],
  name : String,
  delimited : Bool,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  let wanted = if delimited { name } else { name.to_lower() }
  for entry in env {
    let key = if delimited { entry.0 } else { entry.0.to_lower() }
    if key == wanted {
      return entry.1
    }
  }
  raise DataError(message="undefined variable \{name}", span~)
}

///|
/// Runs an operation. A type failure is MISSING in permissive mode and a
/// `TypeError` in strict mode; a data failure is a `DataError` in both modes
/// (spec M4a §4).
fn typed(
  mode : @plan.Mode,
  span : @ast.Span,
  op : () -> @value.Value raise @ops.OpFailure,
) -> @value.Value raise @plan.EvalError {
  op() catch {
    TypeFailure(message) =>
      match mode {
        Permissive => Missing
        Strict => raise TypeError(message~, span~)
      }
    DataFailure(message) => raise DataError(message~, span~)
  }
}

///|
/// The values a wildcard step produces. A value that is not a collection
/// (tuple for `.*`) is its own single element in permissive mode (spec M4a §5).
fn expand(
  v : @value.Value,
  step : @plan.Step,
  mode : @plan.Mode,
  span : @ast.Span,
) -> Array[@value.Value] raise @plan.EvalError {
  try {
    if step is AllFields {
      @ops.all_fields(v)
    } else {
      @ops.all_elements(v)
    }
  } catch {
    TypeFailure(message) =>
      match mode {
        Permissive => if v is Missing { [] } else { [v] }
        Strict => raise TypeError(message~, span~)
      }
    DataFailure(message) => raise DataError(message~, span~)
  } noraise {
    items => items
  }
}

///|
/// A path: one value until a wildcard, then a set of values; later steps apply
/// to each element, and permissive mode drops the elements a step fails on.
fn run_path(
  base : @value.Value,
  steps : Array[@plan.Step],
  env : Array[(String, @value.Value)],
  mode : @plan.Mode,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  let mut single : @value.Value = base
  let mut many : Array[@value.Value]? = None
  for step in steps {
    match step {
      AllElements | AllFields =>
        many = match many {
          None => Some(expand(single, step, mode, span))
          Some(items) => {
            let out = []
            for item in items {
              out.append(expand(item, step, mode, span))
            }
            Some(out)
          }
        }
      _ => {
        let apply = (v : @value.Value) => navigate(v, step, env, mode, span)
        match many {
          None => single = apply(single)
          Some(items) => {
            let out = []
            for item in items {
              let r = apply(item)
              if !(r is Missing) {
                out.push(r)
              }
            }
            many = Some(out)
          }
        }
      }
    }
  }
  match many {
    None => single
    Some(items) => Bag(@value.Bag::new(items))
  }
}

///|
fn navigate(
  v : @value.Value,
  step : @plan.Step,
  env : Array[(String, @value.Value)],
  mode : @plan.Mode,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  match step {
    Field(name, delimited~) =>
      typed(mode, span, () => @ops.field(v, name, delimited~))
    Index(e) => {
      let i = run(e, env, mode)
      let named = e is Const(String(_), _)
      typed(mode, span, () => @ops.index(v, i, named~))
    }
    AllElements | AllFields => v
  }
}

///|
/// An Ion-boxed value as the value it stands for, so that `null.int` is NULL.
fn unboxed(v : @value.Value) -> @value.Value {
  v.lower() catch {
    _ => v
  }
}

///|
fn run_all(
  items : Array[@plan.Expr],
  env : Array[(String, @value.Value)],
  mode : @plan.Mode,
) -> Array[@value.Value] raise @plan.EvalError {
  items.map(item => run(item, env, mode))
}

///|
fn run_tuple(
  fields : Array[(@plan.Expr, @plan.Expr)],
  env : Array[(String, @value.Value)],
  mode : @plan.Mode,
) -> @value.Value raise @plan.EvalError {
  let out : Array[(String, @value.Value)] = []
  for field in fields {
    let value = run(field.1, env, mode)
    match run(field.0, env, mode) {
      String(key) => if !(value is Missing) { out.push((key, value)) }
      Missing => ()
      _ =>
        match mode {
          Permissive => ()
          Strict =>
            raise TypeError(
              message="a struct key must be a string",
              span=span_of(field.0),
            )
        }
    }
  }
  Tuple(@value.Tuple::new(out))
}

///|
/// The map type of a scalar value, if it has one.
fn map_type_of(v : @value.Value) -> @value.MapType? {
  match v {
    Bool(_) => Some(Bool)
    Int(_) => Some(Integer)
    BigInt(_) => Some(BigInt)
    Float(_) => Some(Double)
    Decimal(_) => Some(Decimal)
    String(_) => Some(String)
    Date(_) => Some(Date)
    Time(_) => Some(Time)
    Timestamp(_) => Some(Timestamp)
    _ => None
  }
}

///|
/// The common type of the non-absent values: one type when they agree,
/// DECIMAL when integers and decimals mix, otherwise DYNAMIC.
fn common_type(values : Array[@value.Value]) -> @value.MapType {
  let mut common : @value.MapType? = None
  for v in values {
    if v is (Null | Missing) {
      continue
    }
    let t = map_type_of(v).unwrap_or(Dynamic)
    common = match common {
      None => Some(t)
      Some(c) if c == t => Some(c)
      Some(Integer | Decimal) if t == Decimal || t == Integer => Some(Decimal)
      Some(_) => Some(Dynamic)
    }
  }
  common.unwrap_or(Dynamic)
}

///|
fn widen(v : @value.Value, t : @value.MapType) -> @value.Value {
  match (v, t) {
    (Int(n), Decimal) =>
      try @ion_core.Decimal::parse(n.to_string()) catch {
        _ => v
      } noraise {
        d => Decimal(d)
      }
    _ => v
  }
}

///|
/// `MAP { k: v, ... }`: a NULL or MISSING key drops the entry (permissive) or
/// is the result (strict); a repeated key keeps the last value (permissive) or
/// is an error (strict). The key and value types are inferred.
fn run_map(
  entries : Array[(@plan.Expr, @plan.Expr)],
  env : Array[(String, @value.Value)],
  mode : @plan.Mode,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  let pairs : Array[(@value.Value, @value.Value)] = []
  for entry in entries {
    let key = run(entry.0, env, mode)
    let value = run(entry.1, env, mode)
    if key is (Null | Missing) {
      match mode {
        Permissive => continue
        Strict => return key
      }
    }
    pairs.push((key, value))
  }
  let key_type = match common_type(pairs.map(p => p.0)) {
    Dynamic if pairs.is_empty() => @value.MapType::String
    t => t
  }
  let value_type = common_type(pairs.map(p => p.1))
  // Duplicates are found after widening and lowering, as `MapValue::new` does.
  let unique : Array[(@value.Value, @value.Value)] = []
  for pair in pairs {
    let key = widen(pair.0, key_type)
    let key = key.lower() catch { _ => key }
    let entry = (key, widen(pair.1, value_type))
    match unique.search_by(p => @value.eqg(p.0, key)) {
      Some(at) =>
        match mode {
          Permissive => unique[at] = entry
          Strict => raise TypeError(message="a duplicate map key", span~)
        }
      None => unique.push(entry)
    }
  }
  try @value.MapValue::new(key_type~, value_type~, unique) catch {
    err => raise DataError(message=@debug.to_string(err), span~)
  } noraise {
    m => Map(m)
  }
}

///|
/// The result of a predicate under `NOT`: `NOT x`, or `x` itself.
fn negate(
  v : @value.Value,
  negated : Bool,
  mode : @plan.Mode,
  span : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  if negated {
    typed(mode, span, () => @ops.not_(v))
  } else {
    v
  }
}

///|
/// `CASE`: the first branch whose condition is TRUE (searched), or whose
/// `WHEN` value equals the operand (simple); else the default; else NULL.
fn run_case(
  operand : @plan.Expr?,
  branches : Array[(@plan.Expr, @plan.Expr)],
  default : @plan.Expr?,
  env : Array[(String, @value.Value)],
  mode : @plan.Mode,
) -> @value.Value raise @plan.EvalError {
  let subject = match operand {
    Some(e) => Some(run(e, env, mode))
    None => None
  }
  for branch in branches {
    let condition = run(branch.0, env, mode)
    let chosen = match subject {
      Some(v) => @ops.equal(v, condition)
      None => condition
    }
    if unboxed(chosen) is Bool(true) {
      return run(branch.1, env, mode)
    }
  }
  match default {
    Some(e) => run(e, env, mode)
    None => Null
  }
}

///|
fn span_of(e : @plan.Expr) -> @ast.Span {
  match e {
    Const(_, span)
    | Global(_, delimited=_, span)
    | ListOf(_, span)
    | BagOf(_, span)
    | TupleOf(_, span)
    | MapOf(_, span)
    | Path(_, _, span)
    | IsNull(_, negated=_, span)
    | IsMissing(_, negated=_, span)
    | Unary(_, _, span)
    | Binary(_, _, _, span)
    | And(_, _, span)
    | Or(_, _, span)
    | Not(_, span)
    | BoolTest(_, _, negated=_, span)
    | Between(_, low=_, high=_, negated=_, span)
    | In(_, _, negated=_, span)
    | IsType(_, _, negated=_, span)
    | Case(operand=_, branches=_, default=_, span)
    | Coalesce(_, span)
    | NullIf(_, _, span) => span
  }
}

///|
/// Runs a plan against the global bindings `env`.
pub fn run(
  e : @plan.Expr,
  env : Array[(String, @value.Value)],
  mode : @plan.Mode,
) -> @value.Value raise @plan.EvalError {
  match e {
    Const(v, _) => v
    Global(name, delimited~, span) => lookup(env, name, delimited, span)
    ListOf(items, _) => List(run_all(items, env, mode))
    BagOf(items, _) => Bag(@value.Bag::new(run_all(items, env, mode)))
    TupleOf(fields, _) => run_tuple(fields, env, mode)
    Path(base, steps, span) =>
      run_path(run(base, env, mode), steps, env, mode, span)
    IsNull(x, negated~, _) => {
      let v = unboxed(run(x, env, mode))
      Bool((v is Null || v is Missing) != negated)
    }
    IsMissing(x, negated~, _) => {
      let v = unboxed(run(x, env, mode))
      Bool((v is Missing) != negated)
    }
    MapOf(entries, span) => run_map(entries, env, mode, span)
    Unary(op, x, span) => {
      let v = run(x, env, mode)
      typed(mode, span, () => @ops.neg(v, negate=op is Neg))
    }
    Binary(op, l, r, span) => {
      let a = run(l, env, mode)
      let b = run(r, env, mode)
      typed(mode, span, () => @ops.binary(op, a, b))
    }
    And(l, r, span) => {
      let a = run(l, env, mode)
      let b = run(r, env, mode)
      typed(mode, span, () => @ops.and_(a, b))
    }
    Or(l, r, span) => {
      let a = run(l, env, mode)
      let b = run(r, env, mode)
      typed(mode, span, () => @ops.or_(a, b))
    }
    Not(x, span) => {
      let v = run(x, env, mode)
      typed(mode, span, () => @ops.not_(v))
    }
    BoolTest(x, truth, negated~, _) =>
      Bool(@ops.bool_test(run(x, env, mode), truth, negated~))
    Between(x, low~, high~, negated~, span) => {
      let v = run(x, env, mode)
      let lo = run(low, env, mode)
      let hi = run(high, env, mode)
      let above = typed(mode, span, () => @ops.greater_eq(v, lo))
      let below = typed(mode, span, () => @ops.less_eq(v, hi))
      negate(
        typed(mode, span, () => @ops.and_(above, below)),
        negated,
        mode,
        span,
      )
    }
    In(x, c, negated~, span) => {
      let v = run(x, env, mode)
      let items = run(c, env, mode)
      negate(typed(mode, span, () => @ops.in_(v, items)), negated, mode, span)
    }
    IsType(x, t, negated~, span) => {
      let v = run(x, env, mode)
      negate(typed(mode, span, () => @ops.is_type(v, t)), negated, mode, span)
    }
    Case(operand~, branches~, default~, _) =>
      run_case(operand, branches, default, env, mode)
    Coalesce(items, _) => {
      for item in items {
        let v = run(item, env, mode)
        if !(unboxed(v) is (Null | Missing)) {
          return v
        }
      }
      Null
    }
    NullIf(a, b, _) => {
      let x = run(a, env, mode)
      let y = run(b, env, mode)
      if @ops.equal(x, y) is Bool(true) {
        Null
      } else {
        x
      }
    }
  }
}
