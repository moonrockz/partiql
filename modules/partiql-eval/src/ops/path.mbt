///|
/// An operation was applied to a value of the wrong type. The interpreter adds
/// the span and applies the mode rule (spec M4a §4).
pub(all) suberror TypeFailure {
  TypeFailure(String)
} derive(Debug, Eq)

///|
fn boxed(v : @value.Value) -> @value.Value raise TypeFailure {
  v.lower() catch {
    _ => raise TypeFailure("a symbol without text")
  }
}

///|
/// The field `name` of a tuple. Without `delimited` the match ignores ASCII
/// case; the first matching field wins.
pub fn field(
  v : @value.Value,
  name : String,
  delimited~ : Bool,
) -> @value.Value raise TypeFailure {
  match boxed(v) {
    Null => Missing
    Tuple(t) => {
      let wanted = if delimited { name } else { name.to_lower() }
      for entry in t.fields() {
        let key = if delimited { entry.0 } else { entry.0.to_lower() }
        if key == wanted {
          return entry.1
        }
      }
      raise TypeFailure("no field \{name}")
    }
    _ => raise TypeFailure("field \{name} of a value that is not a tuple")
  }
}

///|
/// The element `i` of a list or the value for the key `i` of a map. A NULL or
/// MISSING map key gives NULL or MISSING. A tuple is indexed by a string only
/// when `named` is true: `t[s]` is the path `t.s` for a string literal `s`
/// (or a CAST to a string), not for any expression.
pub fn index(
  v : @value.Value,
  i : @value.Value,
  named~ : Bool,
) -> @value.Value raise TypeFailure {
  match (boxed(v), boxed(i)) {
    (Null, _) => Missing
    (List(items), Int(n)) =>
      if n >= 0L && n < items.length().to_int64() {
        items[n.to_int()]
      } else {
        raise TypeFailure("list index \{n} out of range")
      }
    (Tuple(_) as t, String(name)) if named => field(t, name, delimited=true)
    (Map(_), Null) => Null
    (Map(_), Missing) => Missing
    (Map(m), key) => {
      for entry in m.entries() {
        if entry.0 == key {
          return entry.1
        }
      }
      raise TypeFailure("no such key in the map")
    }
    _ => raise TypeFailure("a value that cannot be indexed that way")
  }
}

///|
/// `[*]`: the items of a list or bag.
pub fn all_elements(v : @value.Value) -> Array[@value.Value] raise TypeFailure {
  match boxed(v) {
    List(items) => items
    Bag(b) => Array::from_iter(b.items().iter())
    _ => raise TypeFailure("[*] of a value that is not a list or bag")
  }
}

///|
/// `.*`: the values of a tuple.
pub fn all_fields(v : @value.Value) -> Array[@value.Value] raise TypeFailure {
  match boxed(v) {
    Tuple(t) => t.fields().iter().map(f => f.1).collect()
    _ => raise TypeFailure(".* of a value that is not a tuple")
  }
}
