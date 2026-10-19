///|
/// Why an operation on values failed. The interpreter adds the span and
/// applies the mode rule (spec M4a §4): a `TypeFailure` is MISSING in
/// permissive mode and a type error in strict mode; a `DataFailure` (a bad
/// value of the right type, such as a division by zero) is an error in both.
/// `Unsupported` marks a valid operation that this version does not evaluate
/// (spec M4d2 §4.1).
pub(all) suberror OpFailure {
  TypeFailure(String)
  DataFailure(String)
  Unsupported(String)
} derive(Debug, Eq)

///|
fn boxed(v : @value.Value) -> @value.Value raise OpFailure {
  v.lower() catch {
    _ => raise TypeFailure("a symbol without text")
  }
}

///|
/// Matches in tuple declaration order; repeated fields never shadow.
pub(all) enum FieldMatch {
  NoField
  One(@value.Value)
  Many(@value.Value, count~ : Int32)
} derive(Debug, Eq)

///|
/// All fields matching a name, ignoring ASCII case for regular identifiers.
pub fn field_match(
  t : @value.Tuple,
  name : String,
  delimited~ : Bool,
) -> FieldMatch {
  let wanted = if delimited { name } else { name.to_lower() }
  let mut found = NoField
  for (key, value) in t.fields() {
    let key = if delimited { key } else { key.to_lower() }
    if key == wanted {
      found = match found {
        NoField => One(value)
        One(first) => Many(first, count=2)
        Many(first, count~) => Many(first, count=count + 1)
      }
    }
  }
  found
}

///|
/// The field `name` of a tuple. Without `delimited` the match ignores ASCII
/// case. With `unique`, repeated matches are a type failure.
pub fn field(
  v : @value.Value,
  name : String,
  delimited~ : Bool,
  unique~ : Bool,
) -> @value.Value raise OpFailure {
  match boxed(v) {
    Null => Missing
    Tuple(t) =>
      match field_match(t, name, delimited~) {
        NoField => raise TypeFailure("no field \{name}")
        One(v) => v
        Many(v, count~) =>
          if unique {
            raise TypeFailure(
              "field \{name} is ambiguous: the tuple has \{count} matching fields",
            )
          } else {
            v
          }
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
  unique~ : Bool,
) -> @value.Value raise OpFailure {
  match (boxed(v), boxed(i)) {
    (Null, _) => Missing
    (List(items), Int(n)) =>
      if n >= 0L && n < items.length().to_int64() {
        items[n.to_int()]
      } else {
        raise TypeFailure("list index \{n} out of range")
      }
    (Tuple(_) as t, String(name)) if named =>
      field(t, name, delimited=true, unique~)
    (Map(_), Null) => Null
    (Map(_), Missing) => Missing
    (Map(m), key) =>
      match map_lookup(m, key) {
        Some(v) => v
        None => raise TypeFailure("no such key in the map")
      }
    _ => raise TypeFailure("a value that cannot be indexed that way")
  }
}

///|
/// `[*]`: the items of a list or bag.
pub fn all_elements(v : @value.Value) -> Array[@value.Value] raise OpFailure {
  match boxed(v) {
    List(items) => items
    Bag(b) => Array::from_iter(b.items().iter())
    _ => raise TypeFailure("[*] of a value that is not a list or bag")
  }
}

///|
/// `.*`: the values of a tuple.
pub fn all_fields(v : @value.Value) -> Array[@value.Value] raise OpFailure {
  match boxed(v) {
    Tuple(t) => t.fields().iter().map(f => f.1).collect()
    _ => raise TypeFailure(".* of a value that is not a tuple")
  }
}
