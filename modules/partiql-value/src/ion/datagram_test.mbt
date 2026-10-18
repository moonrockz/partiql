///|
test "text and binary datagrams preserve PartiQL encodings and order" {
  let values = @partiql_ion.read_text("1 $missing::null $bag::[2, 3] $ion::foo")
  let encoded = @partiql_ion.write_bytes(values)
  @expect.expect_all(soft => {
    soft.expect(values.length()).to_equal(4)
    soft.expect(values[1]).to_equal(@value.Value::Missing)
    soft.expect(@partiql_ion.read_bytes(encoded)).to_equal(values)
    soft
    .expect(@partiql_ion.read_text(@partiql_ion.write_text(values)))
    .to_equal(values)
  })
}

///|
test "transport errors distinguish text, binary, UTF-8 and codec failures" {
  @expect.expect_all(soft => {
    soft
    .expect_call(() => @partiql_ion.read_text("["))
    .to_raise_matching(
      e => e is @partiql_ion.IonDataError::Text(_),
      description="text syntax",
    )
    soft
    .expect_call(() => @partiql_ion.read_bytes(b"\xe0\x01\x00\xea\x21"))
    .to_raise_matching(
      e => e is @partiql_ion.IonDataError::Binary(_),
      description="truncated binary",
    )
    soft
    .expect_call(() => @partiql_ion.read_bytes(b"\xff"))
    .to_raise_matching(
      e => e is @partiql_ion.IonDataError::Utf8,
      description="UTF-8",
    )
    soft
    .expect_call(() => @partiql_ion.read_text("$bag::1"))
    .to_raise_matching(
      e => {
        e
        is @partiql_ion.IonDataError::Codec(
          @partiql_ion.CodecError::Malformed(_)
        )
      },
      description="malformed encoding",
    )
    soft
    .expect_call(() => @partiql_ion.read_text("$future::1"))
    .to_raise_matching(
      e => {
        e
        is @partiql_ion.IonDataError::Codec(
          @partiql_ion.CodecError::Malformed(_)
        )
      },
      description="unknown encoding",
    )
  })
}

///|
test "schema validation collects all raw Ion violations before decoding" {
  let schema = @schema.Schema::load_from_text(
    "$ion_schema_2_0 type::{name: row, type: struct, fields: {a: {type: int, occurs: required}, b: {type: string, occurs: required}}}",
  )
  let validation = @partiql_ion.Validation::elements(schema, "row")
  @expect.expect_all(soft => {
    soft
    .expect(@partiql_ion.read_text("{a: 1, b: \"ok\"}", validation~).length())
    .to_equal(1)
    for
      bytes in [
        @utf8.encode("{a: false, b: 2} {a: \"no\", b: false}"),
        @binary.write_binary(
          @text.read_ion_datagram("{a: false, b: 2} {a: \"no\", b: false}"),
        ),
      ] {
      try @partiql_ion.read_bytes(bytes, validation~) catch {
        @partiql_ion.IonDataError::Violations(vs) => {
          soft.expect(vs.length()).to_equal(4)
          soft.expect(vs[0].path).to_equal("$[0].a")
          soft.expect(vs[3].path).to_equal("$[1].b")
        }
        e => fail(e.message())
      } noraise {
        _ => fail("invalid rows passed")
      }
    }
    soft
    .expect_call(() => {
      @partiql_ion.read_text(
        "",
        validation=@partiql_ion.Validation::elements(schema, "absent"),
      )
    })
    .to_raise_matching(
      e => e is @partiql_ion.IonDataError::Schema(_),
      description="unknown type even on empty input",
    )
  })
}

///|
test "schemas describe physical PartiQL encodings and whole documents" {
  let schema = @schema.Schema::load_from_text(
    "$ion_schema_2_0 type::{name: bag, type: list, annotations: required::[$bag], element: int} type::{name: missing, type: $null_or::int, annotations: required::[$missing]} type::{name: date, type: timestamp, annotations: required::[$date]} type::{name: rows, type: document, element: int, container_length: 2}",
  )
  @expect.expect_all(soft => {
    for
      (name, good, bad) in [
        ("bag", "$bag::[1, 2]", "[1, 2]"),
        ("missing", "$missing::null", "null"),
        ("date", "$date::2020-01-01", "2020-01-01"),
      ] {
      let validation = @partiql_ion.Validation::elements(schema, name)
      soft
      .expect(@partiql_ion.read_text(good, validation~).length())
      .to_equal(1)
      soft
      .expect_call(() => @partiql_ion.read_text(bad, validation~))
      .to_raise_matching(
        e => e is @partiql_ion.IonDataError::Violations(_),
        description=name,
      )
    }
    let validation = @partiql_ion.Validation::document(schema, "rows")
    soft
    .expect(@partiql_ion.read_text("1 2", validation~))
    .to_equal([@value.Value::from_int(1), @value.Value::from_int(2)])
    soft
    .expect_call(() => @partiql_ion.read_text("1 \"no\"", validation~))
    .to_raise_matching(
      e => e is @partiql_ion.IonDataError::Violations(_),
      description="document elements",
    )
  })
}

///|
test "binary inputs resolve shared field names through the caller catalog" {
  let catalog = @ion_core.Catalog::load(
    @text.read_ion_datagram(
      "$ion_shared_symbol_table::{name: \"fields\", version: 1, symbols: [\"a\"]}",
    ),
  )
  let raw = @text.read_ion_datagram(
    "$ion_symbol_table::{imports: [{name: \"fields\", version: 1, max_id: 1}]} {$10: 2}",
  )
  let bytes = @binary.write_binary(raw)
  @expect.expect(@partiql_ion.read_bytes(bytes, catalog~)).to_equal([
    @value.Value::from_tuple(@value.Tuple([("a", @value.Value::from_int(2))])),
  ])
}

///|
test "binary and text readers handle nesting beyond the former default budget" {
  let source = "[".repeat(1024) + "1" + "]".repeat(1024)
  let values = @partiql_ion.read_text(source)
  @expect.expect(
    @partiql_ion.read_bytes(@partiql_ion.write_bytes(values)) == values,
  ).to_be_true()
}
