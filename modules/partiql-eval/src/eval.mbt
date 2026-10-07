///|
pub using @plan {type Mode, type EvalError}

///|
/// The global bindings of an evaluation: names to values.
pub struct Bindings {
  priv entries : Array[(String, @value.Value)]
}

///|
pub fn Bindings::empty() -> Bindings {
  { entries: [], }
}

///|
pub fn Bindings::of_tuple(tuple : @value.Tuple) -> Bindings {
  { entries: Array::from_iter(tuple.fields().iter()), }
}

///|
/// The bindings of an Ion struct, read as PartiQL-encoded Ion. A value that is
/// not a struct is a `DataError`.
pub fn Bindings::of_ion(value : @ion_core.IonValue) -> Bindings raise EvalError {
  let span = @syntax.Span::{ start: 0, end: 0, }
  let decoded = try @partiql_ion.from_ion(value) catch {
    err => raise DataError(message=@debug.to_string(err), span~)
  } noraise {
    v => v
  }
  match decoded {
    Tuple(t) => Bindings::of_tuple(t)
    _ => raise DataError(message="bindings must be a struct", span~)
  }
}

///|
/// Evaluates a statement. Only expression statements run in this version.
pub fn evaluate(
  statement : @syntax.Statement,
  env~ : Bindings,
  mode? : Mode = Permissive,
) -> @value.Value raise EvalError {
  match statement {
    Query(
      { body: Expr(e), with_: [], order_by: [], limit: None, offset: None, .. }
    ) => @interp.run(@lower.lower(e), env.entries, mode)
    Query({ span, .. }) | Error(span) =>
      raise Unsupported(message="queries are not supported yet (M4b)", span~)
  }
}

///|
/// Parses and evaluates a statement. A syntax error raises `Syntax`.
pub fn evaluate_text(
  source : String,
  env~ : Bindings,
  mode? : Mode = Permissive,
) -> @value.Value raise EvalError {
  let statement = try @syntax.parse(source) catch {
    err => raise Syntax(err)
  } noraise {
    s => s
  }
  evaluate(statement, env~, mode~)
}
