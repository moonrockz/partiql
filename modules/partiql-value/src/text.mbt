///|
/// Code-point lexicographic order. (`String::compare` is length-first.)
fn compare_text(a : String, b : String) -> Int32 {
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
fn compare_octets(a : Bytes, b : Bytes) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return if a[i] < b[i] { -1 } else { 1 }
    }
  }
  a.length().compare(b.length())
}
