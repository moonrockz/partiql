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
    _ => []
  }
}

///|
pub impl @shrink.Shrink for ArbValue with fn shrink(self) {
  let out : Array[ArbValue] = children(self.value).map(v => { value: v, })
  match self.value {
    List(items) if items.length() > 0 =>
      out.push({ value: List(items[1:].to_owned()), })
    Int(n) if n != 0L => out.push({ value: Int(n / 2L), })
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
pub impl @shrink.Shrink for ArbIon

///|
pub(all) struct ArbTimestamp {
  value : @value.Timestamp
} derive(Debug)

///|
pub impl @quickcheck.Arbitrary for ArbTimestamp with fn arbitrary(_size, rs) {
  { value: gen_timestamp(rs), }
}

///|
pub impl @shrink.Shrink for ArbTimestamp
