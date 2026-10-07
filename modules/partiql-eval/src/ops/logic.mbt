///|
/// A three-valued operand: TRUE, FALSE, or unknown (NULL or MISSING). Any other
/// value is a `TypeFailure`. Logic does not tell NULL from MISSING: the
/// result of an unknown operand is NULL (partiql-tests logical.ion).
priv enum Truth {
  True
  False
  Unknown
}

///|
fn truth(v : @value.Value) -> Truth raise OpFailure {
  match boxed(v) {
    Bool(true) => True
    Bool(false) => False
    Null | Missing => Unknown
    _ =>
      raise TypeFailure("a logical operator on a value that is not a boolean")
  }
}

///|
/// FALSE if either is FALSE; else NULL if either is unknown; else TRUE.
pub fn and_(a : @value.Value, b : @value.Value) -> @value.Value raise OpFailure {
  match (truth(a), truth(b)) {
    (False, _) | (_, False) => Bool(false)
    (Unknown, _) | (_, Unknown) => Null
    _ => Bool(true)
  }
}

///|
/// TRUE if either is TRUE; else NULL if either is unknown; else FALSE.
pub fn or_(a : @value.Value, b : @value.Value) -> @value.Value raise OpFailure {
  match (truth(a), truth(b)) {
    (True, _) | (_, True) => Bool(true)
    (Unknown, _) | (_, Unknown) => Null
    _ => Bool(false)
  }
}

///|
pub fn not_(a : @value.Value) -> @value.Value raise OpFailure {
  match truth(a) {
    True => Bool(false)
    False => Bool(true)
    Unknown => Null
  }
}

///|
/// `IS [NOT] TRUE | FALSE | UNKNOWN` (`None`): a non-boolean is neither TRUE
/// nor FALSE nor UNKNOWN.
pub fn bool_test(v : @value.Value, wanted : Bool?, negated~ : Bool) -> Bool {
  let x = boxed(v) catch { _ => v }
  let holds = match (wanted, x) {
    (Some(w), Bool(b)) => w == b
    (None, Null | Missing) => true
    _ => false
  }
  holds != negated
}
