// Datetime and interval literals (spec M4a section 4). The parsers live in
// ops, so that CAST reads text with the same rules (spec M4d2 §4.1).

///|
/// A literal that does not parse is a static `DataError`.
fn literal_error(failure : @ops.OpFailure, span : @ast.Span) -> @plan.EvalError {
  match failure {
    TypeFailure(message) | DataFailure(message) | Unsupported(message) =>
      DataError(message~, span~)
  }
}

///|
/// `YYYY-MM-DD`.
pub fn date_literal(
  text : String,
  span~ : @ast.Span,
) -> @value.Date raise @plan.EvalError {
  @ops.parse_date(text) catch {
    e => raise literal_error(e, span)
  }
}

///|
pub fn time_literal(
  text : String,
  precision : Int32?,
  with_tz : Bool,
  span~ : @ast.Span,
) -> @value.Time raise @plan.EvalError {
  @ops.parse_time(text, precision, with_tz) catch {
    e => raise literal_error(e, span)
  }
}

///|
pub fn timestamp_literal(
  text : String,
  precision : Int32?,
  with_tz : Bool,
  span~ : @ast.Span,
) -> @value.Timestamp raise @plan.EvalError {
  @ops.parse_timestamp(text, precision, with_tz) catch {
    e => raise literal_error(e, span)
  }
}

///|
pub fn interval_literal(
  text : String,
  negative~ : Bool,
  qualifier~ : @ast.IntervalQualifier,
  span~ : @ast.Span,
) -> @value.Value raise @plan.EvalError {
  @ops.parse_interval(text, negative~, qualifier~) catch {
    e => raise literal_error(e, span)
  }
}
