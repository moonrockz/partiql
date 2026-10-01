///|
/// Code-point lexicographic order. (`String::compare` is length-first.)
fn compare_text(a : String, b : String) -> Int {
  let ia = a.iter()
  let ib = b.iter()
  while true {
    match (ia.next(), ib.next()) {
      (None, None) => return 0
      (None, Some(_)) => return -1
      (Some(_), None) => return 1
      (Some(x), Some(y)) => if x != y { return if x < y { -1 } else { 1 } }
    }
  }
  0
}

///|
/// Octet lexicographic order. (`Bytes::compare` is length-first.)
fn compare_octets(a : Bytes, b : Bytes) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return if a[i] < b[i] { -1 } else { 1 }
    }
  }
  a.length().compare(b.length())
}

///|
/// Whether `xs` and `ys` are the same multiset under `same`. `same` must be
/// an equivalence relation (then greedy matching is exact).
fn[T] match_multiset(
  xs : ArrayView[T],
  ys : ArrayView[T],
  same : (T, T) -> Bool,
) -> Bool {
  if xs.length() != ys.length() {
    return false
  }
  let used = Array::make(ys.length(), false)
  for x in xs {
    let mut found = false
    for j, y in ys {
      if !used[j] && same(x, y) {
        used[j] = true
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}
