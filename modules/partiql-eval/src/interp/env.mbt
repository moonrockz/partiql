///|
/// The context of one evaluation: the global bindings, the mode, the session
/// time zone and clock (spec M4d2 §4.4, session-clock §5), the instant of the
/// statement once read, and the error of a relation's iterator, which `pull`
/// and `each` raise (see relation.mbt).
pub struct Ctx {
  globals : Array[(String, @value.Value)]
  mode : @plan.Mode
  zone : @ops.ZoneOffset
  clock : @ops.Clock?
  priv mut instant : (Int64, Int32)?
  priv mut failure : @plan.EvalError?
}

///|
/// Build a context for one statement with global bindings and a required mode.
/// Default to UTC and no clock. Clock sampling and relation failure state
/// start empty; create a fresh context for each statement.
#alias(new, deprecated="Use Ctx(...) instead")
pub fn Ctx::Ctx(
  globals : Array[(String, @value.Value)],
  mode~ : @plan.Mode,
  zone~ : @ops.ZoneOffset = @ops.ZoneOffset::utc(),
  clock? : @ops.Clock,
) -> Ctx {
  { globals, mode, zone, clock, instant: None, failure: None, }
}

///|
/// The instant of this statement: the clock is read on first use only, so
/// every reference in the statement sees the same instant (SQL-92 6.8).
fn Ctx::statement_instant(
  self : Ctx,
  name : String,
) -> (Int64, Int32) raise @ops.OpFailure {
  if self.instant is Some(i) {
    return i
  }
  guard self.clock is Some(clock) else {
    raise DataFailure("\{name} needs a clock: pass clock~ to evaluate")
  }
  let at = (clock.now)() catch { _ => raise DataFailure("the clock failed") }
  let i = (at.to_unix_second(), at.nanosecond())
  self.instant = Some(i)
  i
}

///|
/// A binding tuple: a chain of frames, innermost first. A frame points to
/// its outer frame, so a correlated subquery reads the outer row without a
/// copy (spec M4b1 §3).
priv enum Env {
  Top
  Frame(String, @value.Value, Env)
}

///|
/// The value of the innermost variable called `name`. Lowering resolves the
/// case of a name, so the match is exact.
fn Env::find(self : Env, name : String) -> @value.Value? {
  let mut env = self
  while env is Frame(key, value, outer) {
    if key == name {
      return Some(value)
    }
    env = outer
  }
  None
}
