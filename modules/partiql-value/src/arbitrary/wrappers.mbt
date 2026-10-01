///|
pub(all) struct ArbValue {
  value : @value.Value
} derive(Debug)

///|
pub impl @quickcheck.Arbitrary for ArbValue with fn arbitrary(size, rs) {
  { value: gen_value(if size > 8 { 8 } else { size }, rs), }
}

///|
fn children(v : @value.Value) -> Array[@value.Value] {
  match v {
    List(items) => items
    Bag(bag) => bag.items().to_owned()
    Tuple(t) => t.fields().iter().map(pair => pair.1).collect()
    Map(m) =>
      m.entries().iter().flat_map(pair => [pair.0, pair.1].iter()).collect()
    _ => []
  }
}

///|
/// Shrinks towards smaller values: children of collections, shorter
/// collections, and zero for numbers and empty for text.
pub impl @shrink.Shrink for ArbValue with fn shrink(self) {
  let out : Array[ArbValue] = children(self.value).map(v => { value: v, })
  match self.value {
    List(items) if items.length() > 0 =>
      out.push({ value: List(items[1:].to_owned()), })
    Bag(bag) if bag.length() > 0 =>
      out.push({ value: Bag(@value.Bag::new(bag.items()[1:].to_owned())), })
    Tuple(t) if t.length() > 0 =>
      out.push({ value: Tuple(@value.Tuple::new(t.fields()[1:].to_owned())), })
    Int(n) if n != 0L => out.push({ value: Int(n / 2L), })
    BigInt(_) | Float(_) | Decimal(_) => out.push({ value: Int(0L), })
    String(text) if text != "" => out.push({ value: String(""), })
    Ion(x) =>
      try @value.Value::Ion(x).lower() catch {
        _ => ()
      } noraise {
        lowered => out.push({ value: lowered, })
      }
    _ => ()
  }
  out.iter()
}

///|
pub(all) struct ArbIon {
  value : @ion_core.IonValue
} derive(Debug)

///|
pub impl @quickcheck.Arbitrary for ArbIon with fn arbitrary(size, rs) {
  { value: gen_ion(size, rs), }
}

///|
/// Shrinks to the children of containers, and drops annotations.
pub impl @shrink.Shrink for ArbIon with fn shrink(self) {
  let x = self.value
  let out : Array[ArbIon] = []
  if x.has_annotations() {
    out.push({ value: x.with_annotations([]), })
  }
  match x.kind() {
    List(items) | Sexp(items) =>
      for item in items {
        out.push({ value: item, })
      }
    Struct(fields) =>
      for field in fields {
        out.push({ value: field.value(), })
      }
    _ => ()
  }
  out.iter()
}

///|
pub(all) struct ArbTimestamp {
  value : @value.Timestamp
} derive(Debug)

///|
pub impl @quickcheck.Arbitrary for ArbTimestamp with fn arbitrary(_size, rs) {
  { value: gen_timestamp(rs), }
}

///|
/// Shrinks towards 2000-01-01T00:00:00Z: first the date, then the time,
/// then the offset.
pub impl @shrink.Shrink for ArbTimestamp with fn shrink(self) {
  let ts = self.value
  let target_date = @value.Date::new(year=2000, month=1, day=1) catch {
    _ => abort("unreachable: 2000-01-01 is valid")
  }
  let midnight = @value.Time::new(
    hour=0,
    minute=0,
    second=0,
    offset=ts.time.offset,
  ) catch {
    _ => abort("unreachable: midnight is valid")
  }
  let utc_midnight = @value.Time::new(
    hour=0,
    minute=0,
    second=0,
    offset=Some(0),
  ) catch {
    _ => abort("unreachable: midnight is valid")
  }
  let candidates = [
    @value.Timestamp::new(target_date, ts.time),
    @value.Timestamp::new(ts.date, midnight),
    @value.Timestamp::new(ts.date, utc_midnight),
  ]
  candidates
  .filter(c => !(c == ts))
  .map(c => ArbTimestamp::{ value: c, })
  .iter()
}
