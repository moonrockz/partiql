///|
pub using @plan {type Mode, type EvalError}

///|
pub using @ops {type ZoneOffset, type Clock}

///|
/// The global bindings of an evaluation: names to values.
pub struct Bindings {
  priv entries : Array[(String, @value.Value)]
}

///|
/// An environment with no global names.
pub fn Bindings::empty() -> Bindings {
  { entries: [], }
}

///|
/// Bind each retained tuple field, preserving order and duplicate names.
/// Tuple construction has already removed MISSING fields. Ambiguous names
/// are reported when evaluation resolves them.
pub fn Bindings::of_tuple(tuple : @value.Tuple) -> Bindings {
  { entries: Array::from_iter(tuple.fields().iter()), }
}

///|
/// The bindings `entries`, in order. Unlike `of_tuple`, a global whose value
/// is MISSING stays bound.
pub fn Bindings::of_pairs(entries : Array[(String, @value.Value)]) -> Bindings {
  { entries: entries.copy(), }
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
/// Evaluates a statement. A form that this version does not evaluate raises
/// `Unsupported`. `zone` is the session time zone of CAST (default UTC); `clock` gives the
/// statement time of the clock functions (default none: they fail).
pub fn evaluate(
  statement : @syntax.Statement,
  env~ : Bindings,
  mode~ : Mode = Permissive,
  zone~ : ZoneOffset = ZoneOffset::utc(),
  clock? : Clock,
) -> @value.Value raise EvalError {
  match statement {
    Query(q) =>
      @interp.run(
        @lower.lower_query(q),
        @interp.Ctx(env.entries, mode~, zone~, clock?),
      )
    Error(span) =>
      raise Unsupported(message="a statement that could not be read", span~)
  }
}

///|
/// Parses and evaluates a statement. A syntax error raises `Syntax`.
///
/// ```mbt check
/// test {
///   let env = @eval.Bindings::of_pairs([("x", @value.Value(7))])
///   @expect.expect(@eval.evaluate_text("x + 1", env~)).to_equal(@value.Value(8))
/// }
/// ```
pub fn evaluate_text(
  source : String,
  env~ : Bindings,
  mode~ : Mode = Permissive,
  zone~ : ZoneOffset = ZoneOffset::utc(),
  clock? : Clock,
) -> @value.Value raise EvalError {
  let statement = try @syntax.parse(source) catch {
    err => raise Syntax(err)
  } noraise {
    s => s
  }
  evaluate(statement, env~, mode~, zone~, clock?)
}
