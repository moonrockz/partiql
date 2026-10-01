///|
/// A PartiQL bag: an unordered collection that allows duplicates.
pub struct Bag {
  priv items : Array[Value]
} derive(Debug)

///|
pub fn Bag::new(items : Array[Value]) -> Bag {
  { items, }
}

///|
pub fn Bag::items(self : Bag) -> ArrayView[Value] {
  self.items[:]
}

///|
pub fn Bag::length(self : Bag) -> Int {
  self.items.length()
}
