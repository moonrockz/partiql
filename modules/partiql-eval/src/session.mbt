///|
/// Reusable evaluation settings. Evaluation never replaces session bindings.
pub struct Session {
  env : Bindings
  mode : Mode
  zone : ZoneOffset
  clock : Clock?
}

///|
/// Build reusable evaluation settings. Default to empty globals, permissive
/// mode and UTC. Without `clock`, clock functions raise an evaluation error.
/// Each evaluated statement samples the clock at most once.
///
/// ```mbt check
/// test {
///   let session = @eval.Session()
///   @expect.expect(session.evaluate_script("1 + 2; 3 * 4")).to_equal([
///     @value.Value(3),
///     @value.Value(12),
///   ])
/// }
/// ```
#alias(new, deprecated="Use Session(...) instead")
pub fn Session::Session(
  env~ : Bindings = Bindings::empty(),
  mode~ : Mode = Permissive,
  zone~ : ZoneOffset = ZoneOffset::utc(),
  clock? : Clock,
) -> Session {
  { env, mode, zone, clock, }
}

///|
/// Parse and evaluate one statement with this session's settings.
/// Raise `EvalError::Syntax` for invalid text or an evaluation error on failure.
/// Session bindings remain unchanged.
pub fn Session::evaluate(
  self : Session,
  source : String,
) -> @value.Value raise EvalError {
  evaluate_text(
    source,
    env=self.env,
    mode=self.mode,
    zone=self.zone,
    clock?=self.clock,
  )
}

///|
/// Parse the complete script before evaluation, then return results in order.
pub fn Session::evaluate_script(
  self : Session,
  source : String,
) -> Array[@value.Value] raise EvalError {
  let script = @syntax.parse_script(source) catch { e => raise Syntax(e) }
  script.statements.map(statement => {
    evaluate(
      statement,
      env=self.env,
      mode=self.mode,
      zone=self.zone,
      clock?=self.clock,
    )
  })
}

///|
/// Parse once, bind each top-level element to `name`, and evaluate in order.
/// Empty input yields no results. A failure stops evaluation at that element.
pub fn Session::evaluate_each(
  self : Session,
  source : String,
  name~ : String,
  values~ : Array[@value.Value],
) -> Array[@value.Value] raise EvalError {
  let statement = @syntax.parse(source) catch { e => raise Syntax(e) }
  values.map(value => {
    evaluate(
      statement,
      env=self.env.with_value(name, value),
      mode=self.mode,
      zone=self.zone,
      clock?=self.clock,
    )
  })
}

///|
/// Either evaluation or output encoding failed at the session boundary.
pub(all) suberror SessionError {
  Evaluation(EvalError)
  Ion(@partiql_ion.IonDataError)
} derive(Debug)

///|
/// Evaluate a complete script and encode its results as PartiQL Ion text,
/// one value per line. `pretty` controls each value's layout.
/// Raise `SessionError` on evaluation or encoding failure; no partial output
/// is returned. Empty scripts produce an empty string.
pub fn Session::evaluate_ion_text(
  self : Session,
  source : String,
  pretty~ : Bool = false,
) -> String raise SessionError {
  let values = self.evaluate_script(source) catch { e => raise Evaluation(e) }
  @partiql_ion.write_text(values, pretty~) catch {
    e => raise Ion(e)
  }
}

///|
/// Evaluate a complete script and encode its results as one binary Ion
/// datagram. Raise `SessionError` on evaluation or encoding failure; no
/// partial output is returned.
pub fn Session::evaluate_ion_bytes(
  self : Session,
  source : String,
) -> Bytes raise SessionError {
  let values = self.evaluate_script(source) catch { e => raise Evaluation(e) }
  @partiql_ion.write_bytes(values) catch {
    e => raise Ion(e)
  }
}
