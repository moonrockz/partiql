///|
fn pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
}

///|
fn chance(rs : @splitmix.RandomState, percent : Int) -> Bool {
  pick(rs, 100) < percent
}

///|
let edge_int64s : Array[Int64] = [
  0L, 1L, -1L, 9223372036854775807L, -9223372036854775808L, 9007199254740992L, 9007199254740993L,
  -9007199254740993L,
]

///|
let edge_doubles : Array[Double] = [
  0.0, -0.0, 1.0, -1.0, 0.1, 9007199254740992.0, @double.not_a_number, @double.infinity,
  @double.neg_infinity, 5.0e-324,
]

///|
pub fn gen_number(rs : @splitmix.RandomState) -> @value.Value {
  match pick(rs, 6) {
    0 => Int(edge_int64s[pick(rs, edge_int64s.length())])
    1 => Int(rs.next_int64())
    2 => {
      let base = @bigint.BigInt::from_int64(9223372036854775807L)
      @value.Value::integer(
        if chance(rs, 50) {
          base + @bigint.BigInt::from_int(1 + pick(rs, 1000))
        } else {
          -base - @bigint.BigInt::from_int(2 + pick(rs, 1000))
        },
      )
    }
    3 => Float(edge_doubles[pick(rs, edge_doubles.length())])
    4 => Float(rs.next_double() * 1.0e6 - 5.0e5)
    _ => {
      let coefficient = @bigint.BigInt::from_int64(
        edge_int64s[pick(rs, edge_int64s.length())] / 1000L +
        pick(rs, 100).to_int64(),
      )
      Decimal(@ion_core.Decimal::new(coefficient, pick(rs, 12) - 6))
    }
  }
}

///|
let edge_strings : Array[String] = [
  "", "a", "A", "aa", "\u{10000}", "\u{FFFF}", "É", "é",
]

///|
fn gen_string(rs : @splitmix.RandomState) -> String {
  if chance(rs, 50) {
    edge_strings[pick(rs, edge_strings.length())]
  } else {
    let n = pick(rs, 6)
    let chars = Array::makei(n, _ => (0x61 + pick(rs, 26)).unsafe_to_char())
    String::from_array(chars)
  }
}

///|
fn gen_bytes(rs : @splitmix.RandomState) -> Bytes {
  Bytes::makei(pick(rs, 4), _ => pick(rs, 256).to_byte())
}

///|
pub fn gen_date(rs : @splitmix.RandomState) -> @value.Date {
  let edges = [
    (2024, 2, 29),
    (2023, 2, 28),
    (2000, 1, 1),
    (1, 1, 1),
    (9999, 12, 31),
    (1970, 1, 1),
  ]
  let (year, month, day) = if chance(rs, 40) {
    edges[pick(rs, edges.length())]
  } else {
    (1 + pick(rs, 9999), 1 + pick(rs, 12), 1 + pick(rs, 28))
  }
  @value.Date::new(year~, month~, day~) catch {
    _ => abort("unreachable: generated date fields are valid")
  }
}

///|
pub fn gen_time(rs : @splitmix.RandomState) -> @value.Time {
  let precision = pick(rs, 10)
  let unit = [
      1000000000, 100000000, 10000000, 1000000, 100000, 10000, 1000, 100, 10, 1,
    ][precision]
  let nanos = if chance(rs, 20) {
    999999999 / unit * unit
  } else {
    pick(rs, 1000000000) / unit * unit
  }
  let offsets = [
    Some(0),
    Some(1439),
    Some(-1439),
    Some(-480),
    Some(330),
    None,
    None,
  ]
  let (hour, minute, second) = if chance(rs, 30) {
    [(0, 0, 0), (23, 59, 59)][pick(rs, 2)]
  } else {
    (pick(rs, 24), pick(rs, 60), pick(rs, 60))
  }
  @value.Time::new(
    hour~,
    minute~,
    second~,
    nanos~,
    precision~,
    offset=offsets[pick(rs, offsets.length())],
  ) catch {
    _ => abort("unreachable: generated time fields are valid")
  }
}

///|
pub fn gen_timestamp(rs : @splitmix.RandomState) -> @value.Timestamp {
  @value.Timestamp::new(gen_date(rs), gen_time(rs))
}

///|
pub fn gen_interval_ym(rs : @splitmix.RandomState) -> @value.IntervalYM {
  @value.IntervalYM::from_parts(
    negative=chance(rs, 50),
    years=pick(rs, 1000).to_int64(),
    months=pick(rs, 30).to_int64(),
  ) catch {
    _ => abort("unreachable: generated interval parts fit Int64")
  }
}

///|
pub fn gen_interval_dt(rs : @splitmix.RandomState) -> @value.IntervalDT {
  @value.IntervalDT::from_parts(
    negative=chance(rs, 50),
    days=pick(rs, 1000).to_int64(),
    hours=pick(rs, 30).to_int64(),
    minutes=pick(rs, 90).to_int64(),
    seconds=pick(rs, 90).to_int64(),
    nanos=pick(rs, 2000000000).to_int64(),
  ) catch {
    _ => abort("unreachable: generated interval parts fit Int64")
  }
}

///|
let ion_texts : Array[String] = [
  "sym", "'quoted sym'", "a::b::1", "null.int", "null.sexp", "(1 b \"c\")", "{{\"x\"}}",
  "{{eA==}}", "2017T", "2017-01-01T00:00-00:00", "1.50", "nan", "[a, (b)]", "{x: y::1}",
]

///|
pub fn gen_ion(size : Int, rs : @splitmix.RandomState) -> @ion_core.IonValue {
  ignore(size)
  @text.read_ion(ion_texts[pick(rs, ion_texts.length())]) catch {
    _ => abort("unreachable: ion_texts holds valid Ion")
  }
}

///|
pub fn gen_value(size : Int, rs : @splitmix.RandomState) -> @value.Value {
  let leaf = size <= 0 || chance(rs, 40)
  if leaf {
    match pick(rs, 12) {
      0 => Null
      1 => Missing
      2 => Bool(chance(rs, 50))
      3 | 4 => gen_number(rs)
      5 => String(gen_string(rs))
      6 =>
        if chance(rs, 50) {
          Clob(gen_bytes(rs))
        } else {
          Blob(gen_bytes(rs))
        }
      7 => Date(gen_date(rs))
      8 => Time(gen_time(rs))
      9 => Timestamp(gen_timestamp(rs))
      10 =>
        if chance(rs, 50) {
          IntervalYM(gen_interval_ym(rs))
        } else {
          IntervalDT(gen_interval_dt(rs))
        }
      _ => Ion(gen_ion(size, rs))
    }
  } else {
    let n = pick(rs, 4)
    let child = size / 2
    match pick(rs, 3) {
      0 => List(Array::makei(n, _ => gen_value(child, rs)))
      1 => Bag(@value.Bag::new(Array::makei(n, _ => gen_value(child, rs))))
      _ => {
        let names = ["a", "b", "A"]
        Tuple(
          @value.Tuple::new(
            Array::makei(n, _ => (names[pick(rs, 3)], gen_value(child, rs))),
          ),
        )
      }
    }
  }
}

///|
/// Whether a collection or tuple inside `v` holds NULL or MISSING.
pub fn has_nested_absent(v : @value.Value) -> Bool {
  fn inside(x : @value.Value) -> Bool {
    match x {
      Null | Missing => true
      List(items) => items.iter().any(inside)
      Bag(bag) => bag.items().iter().any(inside)
      Tuple(t) => t.fields().iter().any(pair => inside(pair.1))
      Ion(i) => i.is_null() || ion_has_null(i)
      _ => false
    }
  }
  match v {
    List(items) => items.iter().any(inside)
    Bag(bag) => bag.items().iter().any(inside)
    Tuple(t) => t.fields().iter().any(pair => inside(pair.1))
    Ion(i) => ion_has_null(i)
    _ => false
  }
}

///|
fn ion_has_null(i : @ion_core.IonValue) -> Bool {
  match i.kind() {
    List(items) | Sexp(items) =>
      items.iter().any(x => x.is_null() || ion_has_null(x))
    Struct(fields) =>
      fields.iter().any(f => f.value().is_null() || ion_has_null(f.value()))
    _ => false
  }
}
