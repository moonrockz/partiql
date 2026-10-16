// CAST to LIST, BAG, TUPLE and MAP (spec M4d2 §5.6, RFC 0104).

///|
fn to_collection(
  x : @value.Value,
  target : CastTarget,
) -> @value.Value raise OpFailure {
  match (x, target) {
    (List(_), List) | (Bag(_), Bag) | (Tuple(_), Tuple) => x
    // The stored order of the bag (RFC 0035).
    (Bag(b), List) => List(Array::from_iter(b.items().iter()))
    (List(items), Bag) => Bag(@value.Bag::new(items))
    _ => raise TypeFailure("CAST of \{kind_name(x)} to \{target_name(target)}")
  }
}

///|
/// MAP<K, V> from a tuple (K a text type: field names are keys) or a map:
/// each key is cast to K and each value to V; a MISSING value drops its
/// entry; of two equal keys the last one wins (partiql-tests map.ion).
fn to_map(
  x : @value.Value,
  key : CastTarget,
  key_type : @value.MapType,
  value : CastTarget,
  value_type : @value.MapType,
  zone : ZoneOffset,
  today : () -> @value.Date raise OpFailure,
) -> @value.Value raise OpFailure {
  let entries : Array[(@value.Value, @value.Value)] = match x {
    Tuple(t) => {
      guard key is Text(_) else {
        raise TypeFailure("CAST of a tuple to a MAP whose key type is not text")
      }
      t.fields().iter().map(f => (@value.Value::String(f.0), f.1)).collect()
    }
    Map(m) => Array::from_iter(m.entries().iter())
    _ => raise TypeFailure("CAST of \{kind_name(x)} to MAP")
  }
  let out : Array[(@value.Value, @value.Value)] = []
  for entry in entries {
    let k = cast(entry.0, key, zone~, today~)
    let v = cast(entry.1, value, zone~, today~)
    if v is Missing {
      continue
    }
    match out.search_by(p => @value.eqg(p.0, k)) {
      Some(at) => out[at] = (k, v)
      None => out.push((k, v))
    }
  }
  let built = @value.MapValue::new(key_type~, value_type~, out) catch {
    _ => raise TypeFailure("a MAP key that is not valid for its type")
  }
  Map(built)
}
