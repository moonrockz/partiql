///|
fn ion(text : String) -> @ion_core.IonValue raise {
  @text.read_ion(text)
}

///|
test "untyped null decodes to NULL" {
  @expect.expect(@partiql_ion.from_ion(ion("null"))).to_equal(
    @value.Value::Null,
  )
}

///|
test "$missing::null decodes to MISSING" {
  @expect.expect(@partiql_ion.from_ion(ion("$missing::null"))).to_equal(
    @value.Value::Missing,
  )
}

///|
test "values not in the M0 model are unsupported" {
  let value = ion("1")
  try @partiql_ion.from_ion(value) catch {
    @partiql_ion.CodecError::Unsupported(_) => ()
  } noraise {
    decoded => fail("expected Unsupported, got \{@debug.to_string(decoded)}")
  }
}

///|
test "absent values round-trip through Ion" {
  for text in ["null", "$missing::null"] {
    let original = ion(text)
    let encoded = @partiql_ion.to_ion(@partiql_ion.from_ion(original))
    @expect.expect(encoded.equals(original), label=text).to_be_true()
  }
}
