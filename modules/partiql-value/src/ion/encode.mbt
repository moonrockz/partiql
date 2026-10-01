///|
fn annotate(x : @ion_core.IonValue, name : String) -> @ion_core.IonValue {
  x.with_annotations([@ion_core.SymbolToken::new(name), ..x.annotations()])
}

///|
fn int64(n : Int64) -> @ion_core.IonValue {
  @ion_core.IonValue::big_int(@bigint.BigInt::from_int64(n))
}

///|
fn small(n : Int) -> @ion_core.IonValue {
  @ion_core.IonValue::int(n)
}

///|
fn seconds_decimal(t : @value.Time) -> @ion_core.IonValue {
  let unit = 10N.pow(@bigint.BigInt::from_int(t.precision))
  let fraction = @bigint.BigInt::from_int(t.nanos) /
    10N.pow(@bigint.BigInt::from_int(9 - t.precision))
  let coefficient = @bigint.BigInt::from_int(t.second) * unit + fraction
  @ion_core.IonValue::decimal(@ion_core.Decimal::new(coefficient, -t.precision))
}

///|
fn offset_value(offset : Int?) -> @ion_core.IonValue {
  match offset {
    Some(minutes) => small(minutes)
    None => @ion_core.IonValue::untyped_null()
  }
}

///|
fn struct_of(
  fields : Array[(String, @ion_core.IonValue)],
) -> @ion_core.IonValue {
  @ion_core.IonValue::from_fields(
    fields.map(pair => @ion_core.Field::new(pair.0, pair.1)),
  )
}

///|
fn sign_value(negative : Bool) -> @ion_core.IonValue {
  @ion_core.IonValue::string(if negative { "-" } else { "+" })
}

///|
/// Encodes a value in canonical PartiQL-encoded Ion.
pub fn to_ion(v : @value.Value) -> @ion_core.IonValue {
  match v {
    Null => @ion_core.IonValue::untyped_null()
    Missing => annotate(@ion_core.IonValue::untyped_null(), "$missing")
    Bool(b) => @ion_core.IonValue::bool(b)
    Int(n) => int64(n)
    BigInt(n) => @ion_core.IonValue::big_int(n)
    Float(d) => @ion_core.IonValue::float(d)
    Decimal(d) => @ion_core.IonValue::decimal(d)
    String(s) => @ion_core.IonValue::string(s)
    Clob(bytes) => @ion_core.IonValue::clob(bytes)
    Blob(bytes) => @ion_core.IonValue::blob(bytes)
    Date(d) =>
      annotate(
        struct_of([
          ("year", small(d.year)),
          ("month", small(d.month)),
          ("day", small(d.day)),
        ]),
        "$date",
      )
    Time(t) =>
      annotate(
        struct_of([
          ("hour", small(t.hour)),
          ("minute", small(t.minute)),
          ("second", seconds_decimal(t)),
          ("offset", offset_value(t.offset)),
        ]),
        "$time",
      )
    Timestamp(ts) =>
      annotate(
        struct_of([
          ("year", small(ts.date.year)),
          ("month", small(ts.date.month)),
          ("day", small(ts.date.day)),
          ("hour", small(ts.time.hour)),
          ("minute", small(ts.time.minute)),
          ("second", seconds_decimal(ts.time)),
          ("offset", offset_value(ts.time.offset)),
        ]),
        "$timestamp",
      )
    IntervalYM(i) =>
      annotate(
        struct_of([
          ("sign", sign_value(i.is_negative())),
          ("years", int64(i.years())),
          ("months", int64(i.months_part())),
        ]),
        "$interval_ym",
      )
    IntervalDT(i) =>
      annotate(
        struct_of([
          ("sign", sign_value(i.is_negative())),
          ("days", int64(i.days())),
          ("hours", int64(i.hours())),
          ("minutes", int64(i.minutes())),
          ("seconds", int64(i.seconds_part())),
          ("nanos", int64(i.nanos_part())),
        ]),
        "$interval_dt",
      )
    List(items) => @ion_core.IonValue::list(items.map(to_ion))
    Bag(bag) =>
      annotate(
        @ion_core.IonValue::list(bag.items().iter().map(to_ion).collect()),
        "$bag",
      )
    Tuple(t) =>
      struct_of(
        t.fields().iter().map(pair => (pair.0, to_ion(pair.1))).collect(),
      )
    Map(m) => {
      let pairs = m
        .entries()
        .iter()
        .map(pair => @ion_core.IonValue::list([to_ion(pair.0), to_ion(pair.1)]))
        .collect()
      @ion_core.IonValue::list(pairs).with_annotations([
        @ion_core.SymbolToken::new("$map"),
        @ion_core.SymbolToken::new(m.key_type.name()),
        @ion_core.SymbolToken::new(m.value_type.name()),
      ])
    }
    Graph(g) => encode_graph(g)
    Ion(x) => annotate(x, "$ion")
  }
}

///|
fn symbol(text : String) -> @ion_core.IonValue {
  @ion_core.IonValue::symbol(text)
}

///|
/// The fields shared by nodes and edges: labels when there are any, and the
/// payload when there is one.
fn element_fields(
  labels : Array[String],
  payload : @value.Value?,
) -> Array[(String, @ion_core.IonValue)] {
  let out : Array[(String, @ion_core.IonValue)] = []
  if !labels.is_empty() {
    out.push(
      (
        "labels",
        @ion_core.IonValue::list(labels.map(@ion_core.IonValue::string)),
      ),
    )
  }
  if payload is Some(p) {
    out.push(("payload", to_ion(p)))
  }
  out
}

///|
/// `$graph::{nodes: [...], edges: [...]}` (the external graph format).
fn encode_graph(g : @value.GraphValue) -> @ion_core.IonValue {
  let nodes = g
    .nodes()
    .iter()
    .map(n => {
      struct_of([("id", symbol(n.id)), ..element_fields(n.labels, n.payload)])
    })
    .collect()
  let edges = g
    .edges()
    .iter()
    .map(e => {
      let ends = match e.ends {
        Directed(from~, to~) =>
          @ion_core.IonValue::sexp([symbol(from), symbol("->"), symbol(to)])
        Undirected(a, b) =>
          @ion_core.IonValue::sexp([symbol(a), symbol("--"), symbol(b)])
      }
      struct_of(
        [
          ("id", symbol(e.id)),
          ..element_fields(e.labels, e.payload),
          ("ends", ends),
        ],
      )
    })
    .collect()
  annotate(
    struct_of([
      ("nodes", @ion_core.IonValue::list(nodes)),
      ("edges", @ion_core.IonValue::list(edges)),
    ]),
    "$graph",
  )
}
