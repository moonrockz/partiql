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
  raise DataError(message="undefined name \{name}", span~)
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
fn span_of(e : @plan.Expr) -> @ast.Span {
  match e {
    Const(_, span)
    | Global(_, delimited=_, span)
    | ListOf(_, span)
    | BagOf(_, span)
    | TupleOf(_, span)
    | MapOf(_, span) => span
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
    MapOf(entries, span) => {
      let pairs = entries.map(entry => {
        (run(entry.0, env, mode), run(entry.1, env, mode))
      })
      try
        @value.MapValue::new(key_type=Dynamic, value_type=Dynamic, pairs)
      catch {
        err => raise DataError(message=@debug.to_string(err), span~)
      } noraise {
        m => Map(m)
      }
    }
  }
}
