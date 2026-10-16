// CAST targets (spec M4d2 §3.2).

///|
/// An interval qualifier must name fields in order, of one class, with a
/// leading precision of at least 1 and a fractional precision of 0 to 9.
fn check_qualifier(
  q : @ast.IntervalQualifier,
  span : @ast.Span,
) -> Unit raise @plan.EvalError {
  ignore(interval_fields(q)) catch {
    _ =>
      raise DataError(message="an interval qualifier that is not valid", span~)
  }
  if q.fractional_precision is Some(f) && (f < 0 || f > 9) {
    raise DataError(message="a fractional precision out of range", span~)
  }
  if q.start_precision is Some(p) && p < 1 {
    raise DataError(message="a leading precision out of range", span~)
  }
}

///|
fn at_least_one(
  n : Int32,
  what : String,
  span : @ast.Span,
) -> Int32 raise @plan.EvalError {
  if n < 1 {
    raise DataError(message="\{what} must be at least 1", span~)
  }
  n
}

///|
/// TIME(p) and TIMESTAMP(p): 0 <= p <= 9.
fn seconds_precision(
  p : Int32?,
  span : @ast.Span,
) -> Int32? raise @plan.EvalError {
  if p is Some(n) && (n < 0 || n > 9) {
    raise DataError(
      message="a fractional seconds precision out of range",
      span~,
    )
  }
  p
}

///|
/// DECIMAL without a precision keeps the scale of the value; DECIMAL(p) is
/// DECIMAL(p, 0); 1 <= p <= 38 and 0 <= s <= p.
fn decimal_scale(
  p : Int32?,
  s : Int32?,
  span : @ast.Span,
) -> @ops.Scale raise @plan.EvalError {
  match p {
    None if s is None => Unconstrained
    None =>
      raise DataError(message="a DECIMAL scale without a precision", span~)
    Some(precision) => {
      let scale = s.unwrap_or(0)
      if precision < 1 || precision > 38 || scale < 0 || scale > precision {
        raise DataError(
          message="DECIMAL(\{precision}, \{scale}) needs 1 <= p <= 38 and 0 <= s <= p",
          span~,
        )
      }
      Fixed(precision~, scale~)
    }
  }
}

///|
fn is_dynamic(t : @ast.DataType) -> Bool {
  t is Custom(id) && id.text.to_upper() == "DYNAMIC"
}

///|
/// MAP<K, V> (RFC 0104): K must be a key type (not DYNAMIC); V is any type
/// that `MapType` names, or DYNAMIC (or ANY) for any value.
fn map_target(
  k : @ast.DataType,
  v : @ast.DataType,
  span : @ast.Span,
) -> @ops.CastTarget raise @plan.EvalError {
  if is_dynamic(k) || k is Any {
    unsupported("a MAP with a DYNAMIC key type", span)
  }
  let key = target(k, span)
  let key_type = match @ops.map_type_of(k) {
    Some(t) => t
    None => unsupported("a MAP with this key type", span)
  }
  let (value, value_type) : (@ops.CastTarget, @value.MapType) = if is_dynamic(v) ||
    v is Any {
    (Any, Dynamic)
  } else {
    let value = target(v, span)
    match @ops.map_type_of(v) {
      Some(t) => (value, t)
      None => unsupported("a MAP with this value type", span)
    }
  }
  Map(key~, key_type~, value~, value_type~)
}

///|
/// The target of `CAST(e AS t)`. A target that no value can have is a static
/// `DataError`; a valid target this version does not evaluate is
/// `Unsupported`.
fn target(
  t : @ast.DataType,
  span : @ast.Span,
) -> @ops.CastTarget raise @plan.EvalError {
  match t {
    Null | Missing =>
      raise DataError(message="CAST to NULL or MISSING is not valid", span~)
    Any => Any
    Bool => Bool
    TinyInt => Integer(Bits8)
    SmallInt => Integer(Bits16)
    Int => Integer(Bits32)
    BigInt => Integer(Bits64)
    Decimal(p, s) | Numeric(p, s) => Decimal(decimal_scale(p, s, span))
    Real => Float(Real)
    Double(None) => Float(Double)
    Double(Some(p)) =>
      if p >= 1 && p <= 24 {
        Float(Real)
      } else if p >= 25 && p <= 53 {
        Float(Double)
      } else {
        raise DataError(message="FLOAT(\{p}) needs 1 <= p <= 53", span~)
      }
    Char(n) => Text(Char(at_least_one(n.unwrap_or(1), "a CHAR length", span)))
    Varchar(Some(n)) => Text(Varchar(at_least_one(n, "a VARCHAR length", span)))
    Varchar(None) | String | Symbol => Text(String)
    Blob => Blob
    Clob => Clob
    Date => Date
    Time(p, with_tz~) =>
      Time(precision=seconds_precision(p, span), zone=with_tz)
    Timestamp(p, with_tz~) =>
      Timestamp(precision=seconds_precision(p, span), zone=with_tz)
    Interval(q) => {
      check_qualifier(q, span)
      Interval(q)
    }
    Struct | Tuple => Tuple
    List => List
    Bag => Bag
    Sexp => unsupported("CAST to SEXP", span)
    Array(_) => unsupported("CAST to ARRAY", span)
    Map(k, v) => map_target(k, v, span)
    Custom(id) => raise DataError(message="unknown type \{id.text}", span~)
  }
}
