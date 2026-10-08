///|
/// The context of one evaluation: the global bindings, the mode, and the
/// error of a relation's iterator, which `pull` and `each` raise (see
/// relation.mbt).
pub struct Ctx {
  globals : Array[(String, @value.Value)]
  mode : @plan.Mode
  priv mut failure : @plan.EvalError?
}

///|
pub fn Ctx::new(
  globals : Array[(String, @value.Value)],
  mode~ : @plan.Mode,
) -> Ctx {
  { globals, mode, failure: None, }
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
