///|
/// An Ion value that has no PartiQL equivalent.
pub(all) suberror LowerError {
  /// A symbol whose text is unknown (a symbol ID that no table defines).
  SymbolWithoutText
} derive(Debug, Eq)

///|
/// Converts an Ion timestamp: missing fields become 0, an unknown offset
/// becomes UTC, and more than 9 fractional digits are truncated.
pub fn timestamp_of_ion(ts : @ion_core.Timestamp) -> Timestamp {
  let (nanos, precision) = match ts.fraction {
    None => (0, 0)
    Some(fraction) => {
      // Int64: `-exponent` must not overflow.
      let digits = -fraction.exponent.to_int64()
      if digits <= 0L {
        (0, 0)
      } else if digits <= 9L {
        let d = digits.to_int()
        let scale = @bigint.BigInt::from_int(pow10(9 - d))
        ((fraction.coefficient * scale).to_int(), d)
      } else {
        // Dropping more digits than the coefficient has leaves 0; never
        // build a power of ten larger than the coefficient.
        let drop = digits - 9L
        if drop > digit_count(fraction.coefficient).to_int64() {
          (0, 9)
        } else {
          let scale = 10N.pow(@bigint.BigInt::from_int64(drop))
          ((fraction.coefficient / scale).to_int(), 9)
        }
      }
    }
  }
  let offset = match ts.offset {
    Some(Known(minutes)) => minutes
    _ => 0
  }
  // An Ion timestamp is always valid, so these constructors do not raise.
  let date = Date::{
    year: ts.year,
    month: ts.month.unwrap_or(1),
    day: ts.day.unwrap_or(1),
  }
  let time = Time::{
    hour: ts.hour.unwrap_or(0),
    minute: ts.minute.unwrap_or(0),
    second: ts.second.unwrap_or(0),
    nanos,
    precision,
    offset: Some(offset),
  }
  { date, time, }
}

///|
fn lower_ion(x : @ion_core.IonValue) -> Value raise LowerError {
  match x.kind() {
    Null(_) => Null
    Bool(b) => Bool(b)
    Int(n) => Value::integer(n)
    Float(d) => Float(d)
    Decimal(d) => Decimal(d)
    Timestamp(ts) => Timestamp(timestamp_of_ion(ts))
    Symbol(token) =>
      match token.text() {
        Some(text) => String(text)
        None => raise SymbolWithoutText
      }
    String(s) => String(s)
    Clob(bytes) => Clob(bytes)
    Blob(bytes) => Blob(bytes)
    List(items) | Sexp(items) => List(items.map(item => Ion(item)))
    Struct(fields) => {
      let pairs : Array[(String, Value)] = []
      for field in fields {
        match field.name().text() {
          Some(name) => pairs.push((name, Ion(field.value())))
          None => raise SymbolWithoutText
        }
      }
      Tuple(Tuple::new(pairs))
    }
  }
}

///|
/// Converts a boxed Ion value to its core value, one level deep. Other
/// values are returned unchanged.
pub fn Value::lower(self : Value) -> Value raise LowerError {
  match self {
    Ion(x) => lower_ion(x)
    other => other
  }
}

///|
/// Lowers recursively, including the children of collections and tuples.
pub fn Value::lower_deep(self : Value) -> Value raise LowerError {
  match self.lower() {
    List(items) => {
      let out : Array[Value] = []
      for item in items {
        out.push(item.lower_deep())
      }
      List(out)
    }
    Bag(bag) => {
      let out : Array[Value] = []
      for item in bag.items() {
        out.push(item.lower_deep())
      }
      Bag(Bag::new(out))
    }
    Tuple(tuple) => {
      let out : Array[(String, Value)] = []
      for pair in tuple.fields() {
        out.push((pair.0, pair.1.lower_deep()))
      }
      Tuple(Tuple::new(out))
    }
    other => other
  }
}
