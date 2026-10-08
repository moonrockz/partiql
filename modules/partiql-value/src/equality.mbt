///|
fn num_of(v : Value) -> Num? {
  match v {
    Int(n) => Some(num_of_int64(n))
    BigInt(n) => Some(num_of_bigint(n))
    Float(d) => Some(num_of_double(d))
    Decimal(d) => Some(num_of_decimal(d))
    _ => None
  }
}

///|
fn lowered(v : Value) -> Value? {
  try v.lower() catch {
    _ => None
  } noraise {
    x => Some(x)
  }
}

///|
/// The spec's `=` for two non-absent, lowered values (spec 4.2 rule 3).
fn deep_equal(a : Value, b : Value) -> Bool {
  match (num_of(a), num_of(b)) {
    (Some(x), Some(y)) =>
      return !(x is NaN) && !(y is NaN) && compare_num(x, y) == 0
    (Some(_), None) | (None, Some(_)) => return false
    _ => ()
  }
  match (a, b) {
    (Bool(x), Bool(y)) => x == y
    (String(x), String(y)) => x == y
    (Clob(x) | Blob(x), Clob(y) | Blob(y)) => x == y
    (Date(x), Date(y)) => x == y
    (Time(x), Time(y)) =>
      match (x.offset, y.offset) {
        (Some(_), Some(_)) => x.utc_key() == y.utc_key()
        (None, None) => x.local_key() == y.local_key()
        _ => false
      }
    (Timestamp(x), Timestamp(y)) =>
      match (x.time.offset, y.time.offset) {
        (Some(_), Some(_)) => x.utc_key() == y.utc_key()
        (None, None) => x.local_key() == y.local_key()
        _ => false
      }
    (IntervalYM(x), IntervalYM(y)) => x == y
    (IntervalDT(x), IntervalDT(y)) => x == y
    (List(xs), List(ys)) =>
      xs.length() == ys.length() &&
      xs.iter().zip(ys.iter()).all(pair => eqg(pair.0, pair.1))
    (Bag(x), Bag(y)) => match_multiset(x.items(), y.items(), eqg)
    (Tuple(x), Tuple(y)) =>
      match_multiset(x.fields(), y.fields(), (p, q) => {
        p.0 == q.0 && eqg(p.1, q.1)
      })
    // Type parameters are ignored (RFC 0104 equality; Kotlin's comparator).
    // Id-based; payloads compared with eqg (spec M1b section 4.2).
    (Graph(x), Graph(y)) => same_graph(x, y, eqg)
    (Map(x), Map(y)) =>
      match_multiset(x.entries(), y.entries(), (p, q) => {
        eqg(p.0, q.0) && eqg(p.1, q.1)
      })
    _ => false
  }
}

///|
/// The PartiQL `=` operator: MISSING if either side is MISSING, else NULL if
/// either side is NULL, else a Bool. Never fails on mixed types.
pub fn sql_equals(a : Value, b : Value) -> Value {
  match (lowered(a), lowered(b)) {
    (Some(x), Some(y)) =>
      match (x, y) {
        (Missing, _) | (_, Missing) => Missing
        (Null, _) | (_, Null) => Null
        _ => Bool(deep_equal(x, y))
      }
    _ => Bool(a == b)
  }
}

///|
/// Grouping equivalence: NULL eqg NULL, MISSING eqg MISSING, NaN eqg NaN;
/// otherwise the same as `=`.
pub fn eqg(a : Value, b : Value) -> Bool {
  match (lowered(a), lowered(b)) {
    (Some(x), Some(y)) =>
      match (x, y) {
        (Null, Null) | (Missing, Missing) => true
        (Null | Missing, _) | (_, Null | Missing) => false
        (Float(p), Float(q)) if p.is_nan() && q.is_nan() => true
        _ => deep_equal(x, y)
      }
    _ => a == b
  }
}

///|
/// The digits of an exact number without trailing zeros of its coefficient,
/// so that numbers that are equal have one key.
fn number_key(n : Num) -> String {
  match n {
    NaN => "nan"
    NegInf => "-inf"
    PosInf => "+inf"
    Finite(c, e) => {
      let text = c.to_string()
      let mut end = text.length()
      let mut exponent = e
      while end > 1 && text[end - 1] == '0' {
        end -= 1
        exponent += 1
      }
      "n\{text[:end].to_owned()}e\{exponent}"
    }
  }
}

///|
fn bytes_key(b : Bytes) -> String {
  let out = StringBuilder()
  for i in 0..<b.length() {
    out.write_string(b[i].to_int().to_string())
    out.write_char(',')
  }
  out.to_string()
}

///|
fn clock_key(t : Time) -> String {
  let (s, n) = if t.offset is Some(_) { t.utc_key() } else { t.local_key() }
  "\{t.offset is Some(_)}:\{s}:\{n}"
}

///|
fn group_key_at(v : Value, depth : Int) -> String {
  let sub = (x : Value) => group_key_at(x, depth - 1)
  match lowered(v) {
    None => "x"
    Some(x) =>
      match x {
        Null => "N"
        Missing => "M"
        Bool(b) => "b\{b}"
        String(s) => "s\{s}"
        Clob(b) | Blob(b) => "y" + bytes_key(b)
        Date(d) => "d\{d.year}-\{d.month}-\{d.day}"
        Time(t) => "t" + clock_key(t)
        Timestamp(t) => {
          let (s, n) = if t.time.offset is Some(_) {
            t.utc_key()
          } else {
            t.local_key()
          }
          "T\{t.time.offset is Some(_)}:\{s}:\{n}"
        }
        IntervalYM(i) => "ym\{i.months}"
        IntervalDT(i) => "dt\{i.seconds}:\{i.nanos}"
        List(items) =>
          if depth > 0 {
            "l[" + items.map(sub).join(",") + "]"
          } else {
            "l\{items.length()}"
          }
        Bag(b) =>
          if depth > 0 {
            let keys = b.items().map(sub)
            keys.sort()
            "b[" + keys.join(",") + "]"
          } else {
            "g\{b.length()}"
          }
        Tuple(t) =>
          if depth > 0 {
            let keys = t.fields().map(f => "\{f.0}=" + sub(f.1))
            keys.sort()
            "u[" + keys.join(",") + "]"
          } else {
            "u\{t.length()}"
          }
        Map(m) =>
          if depth > 0 {
            let keys = m.entries().map(e => sub(e.0) + "=" + sub(e.1))
            keys.sort()
            "m[" + keys.join(",") + "]"
          } else {
            "m\{m.entries().length()}"
          }
        Graph(_) => "G"
        Ion(_) => "x"
        _ =>
          match num_of(x) {
            Some(n) => number_key(n)
            None => "?"
          }
      }
  }
}

///|
/// A key that values which are `eqg` share, for hashing (the DISTINCT of
/// SELECT, GROUP BY). It reads two levels into a collection, deeper values
/// by kind and size only, so it takes no deep recursion; values that differ
/// only below that share a key.
pub fn group_key(v : Value) -> String {
  group_key_at(v, 2)
}
