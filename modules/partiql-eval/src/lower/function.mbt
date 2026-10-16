// Built-in scalar function calls (spec M4d1 §3).

///|
/// How many arguments a built-in takes.
priv enum Arity {
  Exactly(Int32)
  Between(Int32, Int32)
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
    "ABS" => Some((Abs, Exactly(1)))
    "MOD" => Some((Mod, Exactly(2)))
    "TEXT_REPLACE" => Some((TextReplace, Exactly(3)))
    "UPPER" => Some((Upper, Exactly(1)))
    "LOWER" => Some((Lower, Exactly(1)))
    "TO_STRING" => Some((ToString, Exactly(2)))
    "TO_TIMESTAMP" => Some((ToTimestamp, Between(1, 2)))
    "UTCNOW" => Some((UtcNow, Exactly(0)))
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
  if arity is Between(low, high) &&
    (args.length() < low || args.length() > high) {
    raise DataError(
      message="\{f.name()} takes \{low} to \{high} arguments",
      span~,
    )
  }
  // A collection argument is not coerced from a subquery to a scalar
  // (spec M4d1 §3.4; partiql-tests size.ion:242, basic.ion:61).
  let lower_arg = match f {
    Size | Cardinality | Exists => lower_plain
    _ => lower_at
  }
  Call(f, args.map(x => lower_arg(x, scope, depth)), span)
}

///|
/// A special form (TRIM, SUBSTRING, POSITION, OVERLAY) with its arguments in
/// the fixed positions of `Function`. The syntax tree fixes their number.
fn special_call(
  f : @plan.Function,
  args : Array[@ast.Expr],
  scope : Scope,
  depth : Int32,
  span : @ast.Span,
) -> @plan.Expr raise @plan.EvalError {
  Call(f, args.map(x => lower_at(x, scope, depth)), span)
}

///|
/// DATE_ADD and DATE_DIFF take the fields YEAR to SECOND; a time zone field
/// is a static error (partiql-tests date_diff.ion:2009, :2020).
fn check_date_part(
  f : @ast.DatetimeField,
  name : String,
  span : @ast.Span,
) -> Unit raise @plan.EvalError {
  if f is (TimezoneHour | TimezoneMinute) {
    raise DataError(message="\{name} does not take a time zone field", span~)
  }
}

///|
/// The precision of CURRENT_TIME or CURRENT_TIMESTAMP: the default when it is
/// not given (TIME 0, TIMESTAMP 6, SQL-92 6.1); 0 to 9.
fn clock_precision(
  p : Int32?,
  default : Int32,
  span : @ast.Span,
) -> Int32 raise @plan.EvalError {
  let n = p.unwrap_or(default)
  if n < 0 || n > 9 {
    raise DataError(
      message="a fractional seconds precision out of range",
      span~,
    )
  }
  n
}

///|
/// A call to a name that is neither an aggregate nor a built-in: a static
/// error (SQL: no such routine), at the name.
fn unknown_function(id : @ast.Identifier) -> @plan.EvalError {
  DataError(message="unknown function \{id.text}", span=id.span)
}
