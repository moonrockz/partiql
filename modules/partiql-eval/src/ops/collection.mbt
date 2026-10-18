// The collection and map functions (spec M4d1 §5).

///|
/// The number of elements, fields or entries. Duplicate fields and NULL or
/// MISSING elements count (partiql-tests cardinality.ion:122, exists.ion:74).
fn element_count(name : String, v : @value.Value) -> Int32 raise OpFailure {
  match v {
    List(items) => items.length()
    Bag(b) => b.length()
    Tuple(t) => t.length()
    Map(m) => m.length()
    _ => raise TypeFailure("\{name} of a value that is not a collection")
  }
}

///|
/// `SIZE(c)`.
pub fn size(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("SIZE", [Collection], args, xs => {
    @value.Value::from_int(element_count("SIZE", xs[0]).to_int64())
  })
}

///|
/// `CARDINALITY(c)`, the same count as SIZE.
pub fn cardinality(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("CARDINALITY", [Collection], args, xs => {
    @value.Value::from_int(element_count("CARDINALITY", xs[0]).to_int64())
  })
}

///|
/// `EXISTS(c)`: whether `c` has an element.
pub fn exists(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("EXISTS", [Collection], args, xs => {
    @value.Value::from_bool(element_count("EXISTS", xs[0]) > 0)
  })
}

///|
/// `TUPLEUNION(t1, ..., tn)`: every field of every argument, in argument
/// order, duplicates kept (spec select.adoc:585-593).
pub fn tuple_union(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("TUPLEUNION", Array::make(args.length(), Param::Tuple), args, xs => {
    let fields : Array[(String, @value.Value)] = []
    for x in xs {
      match x {
        Tuple(t) => t.fields().each(f => fields.push(f))
        _ => raise TypeFailure("TUPLEUNION of a value that is not a tuple")
      }
    }
    @value.Value::from_tuple(@value.Tuple(fields))
  })
}

///|
/// The value for `key` in `m`, matched by value (`eqg`, so `1` finds `1.0`),
/// or None. A key outside the map's key type family (`MapType::admits`) is a
/// `TypeFailure` (RFC 0104: compatible types are cast, others are an error).
fn map_lookup(
  m : @value.MapValue,
  key : @value.Value,
) -> @value.Value? raise OpFailure {
  if !m.key_type.admits(key) {
    raise TypeFailure("a map key of an incompatible type")
  }
  for entry in m.entries() {
    if @value.eqg(entry.0, key) {
      return Some(entry.1)
    }
  }
  None
}

///|
/// `MAP_GET(m, k)`: `m[k]`; an absent key is a `TypeFailure` (RFC 0104).
pub fn map_get(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("MAP_GET", [Map, Any], args, xs => {
    match xs {
      [Map(m), key] =>
        match map_lookup(m, key) {
          Some(v) => v
          None => raise TypeFailure("no such key in the map")
        }
      _ => raise TypeFailure("MAP_GET of a value that is not a map")
    }
  })
}

///|
/// `MAP_CONTAINS_KEY(m, k)`.
pub fn map_contains_key(
  args : Array[@value.Value],
) -> @value.Value raise OpFailure {
  apply("MAP_CONTAINS_KEY", [Map, Any], args, xs => {
    match xs {
      [Map(m), key] => @value.Value::from_bool(map_lookup(m, key) is Some(_))
      _ => raise TypeFailure("MAP_CONTAINS_KEY of a value that is not a map")
    }
  })
}

///|
/// The entries of a map argument, for MAP_KEYS, MAP_VALUES and MAP_ENTRIES.
fn map_bag(
  name : String,
  args : Array[@value.Value],
  item : ((@value.Value, @value.Value)) -> @value.Value,
) -> @value.Value raise OpFailure {
  apply(name, [Map], args, xs => {
    match xs {
      [Map(m)] =>
        @value.Value::from_bag(
          @value.Bag(m.entries().iter().map(item).collect()),
        )
      _ => raise TypeFailure("\{name} of a value that is not a map")
    }
  })
}

///|
/// `MAP_KEYS(m)`: a bag of the keys in insertion order.
pub fn map_keys(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  map_bag("MAP_KEYS", args, e => e.0)
}

///|
/// `MAP_VALUES(m)`: a bag of the values in insertion order.
pub fn map_values(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  map_bag("MAP_VALUES", args, e => e.1)
}

///|
/// `MAP_ENTRIES(m)`: a bag of `{k, v}` tuples (partiql-tests map.ion:956).
pub fn map_entries(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  map_bag("MAP_ENTRIES", args, e => {
    @value.Value::from_tuple(@value.Tuple([("k", e.0), ("v", e.1)]))
  })
}
