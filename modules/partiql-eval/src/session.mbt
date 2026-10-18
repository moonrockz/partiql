///|
/// Reusable evaluation settings. Evaluation never replaces session bindings.
pub struct Session {
  env : Bindings
  mode : Mode
  zone : ZoneOffset
  clock : Clock?
}

///|
pub fn Session::new(
  env~ : Bindings = Bindings::empty(),
  mode~ : Mode = Permissive,
  zone~ : ZoneOffset = ZoneOffset::utc(),
  clock? : Clock,
) -> Session {
  { env, mode, zone, clock, }
}

///|
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
pub fn Session::evaluate_ion_bytes(
  self : Session,
  source : String,
) -> Bytes raise SessionError {
  let values = self.evaluate_script(source) catch { e => raise Evaluation(e) }
  @partiql_ion.write_bytes(values) catch {
    e => raise Ion(e)
  }
}
