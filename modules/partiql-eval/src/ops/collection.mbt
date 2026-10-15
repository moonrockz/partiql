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
    Int(element_count("SIZE", xs[0]).to_int64())
  })
}

///|
/// `CARDINALITY(c)`, the same count as SIZE.
pub fn cardinality(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("CARDINALITY", [Collection], args, xs => {
    Int(element_count("CARDINALITY", xs[0]).to_int64())
  })
}

///|
/// `EXISTS(c)`: whether `c` has an element.
pub fn exists(args : Array[@value.Value]) -> @value.Value raise OpFailure {
  apply("EXISTS", [Collection], args, xs => {
    Bool(element_count("EXISTS", xs[0]) > 0)
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
    Tuple(@value.Tuple::new(fields))
  })
}
