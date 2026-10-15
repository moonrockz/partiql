// Built-in scalar function calls (spec M4d1 §3).

///|
/// How many arguments a built-in takes.
priv enum Arity {
  Exactly(Int32)
  AnyCount
}

///|
/// The built-in a call names. A regular name matches without regard to
/// case; a delimited name never matches (spec M4d1 §3.1). TRIM, SUBSTRING,
/// POSITION and OVERLAY are not here: the parser gives them their own
/// syntax tree nodes, also for their comma forms.
fn builtin(id : @ast.Identifier) -> (@plan.Function, Arity)? {
  if id.delimited {
    return None
  }
  match id.text.to_upper() {
    "CHAR_LENGTH" | "CHARACTER_LENGTH" => Some((CharLength, Exactly(1)))
    "OCTET_LENGTH" => Some((OctetLength, Exactly(1)))
    "BIT_LENGTH" => Some((BitLength, Exactly(1)))
    "SIZE" => Some((Size, Exactly(1)))
    "CARDINALITY" => Some((Cardinality, Exactly(1)))
    "EXISTS" => Some((Exists, Exactly(1)))
    "TUPLEUNION" => Some((TupleUnion, AnyCount))
    "MAP_GET" => Some((MapGet, Exactly(2)))
    "MAP_CONTAINS_KEY" => Some((MapContainsKey, Exactly(2)))
    "MAP_KEYS" => Some((MapKeys, Exactly(1)))
    "MAP_VALUES" => Some((MapValues, Exactly(1)))
    "MAP_ENTRIES" => Some((MapEntries, Exactly(1)))
    _ => None
  }
}

///|
fn arguments_text(n : Int32) -> String {
  if n == 1 {
    "one argument"
  } else {
    "\{n} arguments"
  }
}

///|
/// `f(args)` for a built-in `f`. A set quantifier or a wrong number of
/// arguments is a static error (spec M4d1 §3.2).
fn scalar_call(
  f : @plan.Function,
  arity : Arity,
  args : Array[@ast.Expr],
  quantifier : @ast.SetQuantifier?,
  scope : Scope,
  depth : Int32,
  span : @ast.Span,
) -> @plan.Expr raise @plan.EvalError {
  if quantifier is Some(_) {
    raise DataError(message="\{f.name()} does not take DISTINCT or ALL", span~)
  }
  if arity is Exactly(n) && args.length() != n {
    raise DataError(message="\{f.name()} takes \{arguments_text(n)}", span~)
  }
  // A collection argument is not coerced from a subquery to a scalar
  // (spec M4d1 §3.4; partiql-tests size.ion:242, basic.ion:61).
  let lower_arg = match f {
    Size | Cardinality | Exists => lower_plain
    _ => lower_at
  }
  Call(f, args.map(x => lower_arg(x, scope, depth)), span)
}
