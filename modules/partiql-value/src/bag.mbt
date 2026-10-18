///|
/// A PartiQL bag: an unordered collection that allows duplicates.
pub struct Bag {
  priv items : Array[Value]
}

///|
/// Build a bag, retaining duplicates and the input order for output.
/// The backing array is shared with `items`; copy it first if it will be mutated.
#alias(new, deprecated="Use Bag(...) instead")
pub fn Bag::Bag(items : Array[Value]) -> Bag {
  { items, }
}

///|
/// A read-only view of the elements in their stored order, including duplicates.
pub fn Bag::items(self : Bag) -> ArrayView[Value] {
  self.items[:]
}

///|
/// The number of elements, counting duplicates.
pub fn Bag::length(self : Bag) -> Int32 {
  self.items.length()
}
