# moonrockz/partiql-value

The PartiQL data model for MoonBit, with structural identity, SQL equality,
grouping equivalence, ordering, and codecs for PartiQL-encoded Ion, JSON and YAML input.

## Installation and imports

```sh
moon add moonrockz/partiql-value
```

Add the packages you use to `moon.pkg`:

```mbt nocheck
import {
  "moonrockz/partiql-value" @value,
  "moonrockz/partiql-value/ion" @partiql_ion,
  "moonrockz/partiql-value/json" @partiql_json,
  "moonrockz/partiql-value/yaml" @partiql_yaml,
  "moonrockz/ion/ion" @ion_core,
}
```

The checked examples use `moonrockz/expect` for assertions. Add it with
`moon add moonrockz/expect` and put this import in `moon.pkg` when copying
the test blocks:

```mbt nocheck
import { "moonrockz/expect" } for "test"
```

| Package | Content |
|---|---|
| `moonrockz/partiql-value` | `Value`, collections, maps, graphs, datetime and interval types, and value relations |
| `moonrockz/partiql-value/ion` | Single-value codecs, text/binary datagrams and Ion Schema validation |
| `moonrockz/partiql-value/json` | Strict JSON documents with exact numbers and duplicate keys |
| `moonrockz/partiql-value/yaml` | YAML 1.2 Core input, exact numbers and bounded aliases |
| `moonrockz/partiql-value/arbitrary` | Quickcheck generators and shrinkable wrappers |

## Constructing values

`Value(x)` converts `Bool`, `Int`, `Int64`, `BigInt`, `Double`, `String`,
Ion decimals, validated datetime/interval types, `Bag`, `Tuple`, `MapValue`,
`GraphValue` and arrays of convertible elements. An existing `Value` passes
through. A `BigInt` becomes `Int` when it fits Int64. An Ion value is boxed
without lowering it.

```mbt check
test "construct values" {
  let list = @value.Value([1, 2, 3])
  @expect.expect(list).to_equal(@value.Value::from_list([@value.Value::from_int(1), @value.Value::from_int(2), @value.Value::from_int(3)]))
}
```

Use `Value::from_*` when the payload type is known. Every payload-bearing
variant has a typed conversion:

| Payload | Conversion |
|---|---|
| `Bool`, `Int64`, `BigInt` | `from_bool`, `from_int`, `from_bigint` |
| `Double`, Ion `Decimal`, `String` | `from_float`, `from_decimal`, `from_string` |
| `Bytes` | `from_blob` or `from_clob`, chosen explicitly |
| `Date`, `Time`, `Timestamp` | `from_date`, `from_time`, `from_timestamp` |
| `IntervalYM`, `IntervalDT` | `from_interval_ym`, `from_interval_dt` |
| `Array[Value]`, `Bag`, `Tuple` | `from_list`, `from_bag`, `from_tuple` |
| `MapValue`, `GraphValue`, Ion `IonValue` | `from_map`, `from_graph`, `from_ion` |

`from_bigint` normalizes integers to `Int` when they fit Int64. Other typed
conversions retain the payload's kind and storage. Domain constructors
validate inputs; value conversions wrap the validated result. `from_list`
shares its backing array, while generic `Value(array)` maps into a new list.

The concrete parameter types resolve nested domain constructor names:

```mbt check
test "typed bag and date conversions" {
  let bag = @value.Value::from_bag(@value.Bag([@value.Value(1), @value.Value(2)]))
  let date = @value.Value::from_date(@value.Date(year=2024, month=2, day=29))
  @expect.expect_all(soft => {
    soft.expect(bag is @value.Value::Bag(b) && b.length() == 2).to_be_true()
    soft.expect(date is @value.Value::Date(d) && d.day == 29).to_be_true()
  })
}
```

`Tuple(fields)` builds the domain tuple. `Value::from_tuple(tuple)` wraps it
as a PartiQL value and is equivalent to `Value(tuple)`:

```mbt check
test "build and wrap a tuple" {
  let value = @value.Value::from_tuple(@value.Tuple([
    ("a", @value.Value(1)), ("a", @value.Value(2)),
  ]))
  guard value is @value.Value::Tuple(tuple) else {
    fail("expected a tuple value")
  }
  @expect.expect(tuple.get_all("a")).to_equal([@value.Value(1), @value.Value(2)])
}
```

Use enum variants in patterns, as above. They also remain available for
construction for compatibility. `Bag`, `Tuple`, `Date`, `Time`, `Timestamp`,
`IntervalYM` and `IntervalDT` share names with variants, so a standalone
`let tuple = @value.Tuple(fields)` still needs an expected result type or
qualified `Tuple::Tuple(...)`. Prefer typed wrapping functions when building
a `Value`, for example `Value::from_tuple(@value.Tuple(fields))`.

A tuple preserves duplicate names and drops MISSING fields. A bag keeps
MISSING and duplicates. Bags retain the supplied backing array; copy it
before construction if you will mutate it later. Tuple, map and graph
constructors create their own arrays. Collection accessors return read-only
views in stored order.

Use explicit `Value::Null` and `Value::Missing`. Bytes have two meanings,
so choose `Value::from_blob(bytes)` or `Value::from_clob(bytes)` explicitly. Arrays
become lists; use a `Bag` for an unordered collection. Conversions do not
perform SQL CAST coercions.

Implement `ToValue` to support a domain type with `Value(x)`:

```mbt check
struct CustomerId(Int)

impl @value.ToValue for CustomerId with fn to_value(self) {
  @value.Value(self.0)
}

test "domain conversion" {
  @expect.expect(@value.Value(CustomerId(7))).to_equal(@value.Value::from_int(7))
}
```

The former `Type::new(...)` entry points remain deprecated aliases. Replace
them with `Type(...)`, or `Type::Type(...)` where qualification is needed.
`Value::integer` remains available as the legacy spelling of `Value::from_bigint`.

## Datetimes and intervals

Dates use the proleptic Gregorian calendar with years -999999999..999999999.
Times retain fractional precision and an optional offset in minutes east of
UTC; `None` means WITHOUT TIME ZONE. Invalid fields raise `DateTimeError`.
Intervals normalize their parts and raise `IntervalError::Overflow` when the
representation cannot hold the result.

```mbt check
test "datetime and interval constructors" {
  let date : @value.Date = @value.Date(year=2024, month=2, day=29)
  let time : @value.Time = @value.Time(
    hour=12, minute=30, second=0, nanos=125000000, precision=3, offset=Some(60),
  )
  let timestamp : @value.Timestamp = @value.Timestamp(date, time)
  let interval : @value.IntervalDT = @value.IntervalDT(0, -250000000)
  @expect.expect((timestamp.time.precision, interval.is_negative(), interval.nanos_part())).to_equal((3, true, 250000000L))
}
```

## Maps and graphs

`MapValue` checks keys against the declared key family and rejects NULL,
MISSING, nonscalar and duplicate keys. Duplicate keys use grouping equivalence.
MISSING values are dropped after all keys are checked. The declared value
type is metadata; construction does not coerce values to it.

Graphs have separate node and edge id namespaces. Construction rejects
unknown endpoints, duplicate ids within a namespace and MISSING payloads.
Labels are deduplicated; absent payloads use `None`.

```mbt check
test "map and graph constructors" {
  let map = @value.MapValue(
    key_type=@value.MapType::String, value_type=@value.MapType::Dynamic,
    [(@value.Value("a"), @value.Value(1))],
  )
  let node = @value.GraphNode(id="n", labels=["person", "person"])
  let edge = @value.GraphEdge(id="e", ends=@value.Ends::Directed(from="n", to="n"))
  let graph = @value.GraphValue([node], [edge])
  @expect.expect((map.length(), graph.nodes()[0].labels().length(), graph.edges().length())).to_equal((1, 1, 1))
}
```

## Choosing a relation

| Relation | Meaning |
|---|---|
| `==` via `Eq` | Structural identity: same variant and contents; bags and tuples as multisets; decimal scale counts |
| `sql_equals` | SQL equality over values: MISSING takes precedence over NULL; numbers compare across types |
| `eqg` | Grouping equivalence: NULL equals NULL, MISSING equals MISSING, NaN equals NaN |
| `compare` | ORDER BY total order, choosing `NullsFirst` or `NullsLast` |

Boxed Ion values compare through their lowered representation in semantic
relations. Structural identity retains the Ion representation. The evaluator's
`=` operator adds its own absence and datetime rules; use `evaluate_text` for
query semantics.

```mbt check
test "boxed Ion equality" {
  let symbol = @value.Value(@ion_core.IonValue::symbol("hello"))
  @expect.expect(@value.sql_equals(symbol, @value.Value("hello"))).to_equal(@value.Value::from_bool(true))
}
```

`Value::lower` lowers the outer Ion representation; `lower_deep` also lowers
nested Ion. An unresolved symbol raises `LowerError`. `fold` walks deeply
nested values without relying on the call stack.

## Ion codecs and datagrams

`@partiql_ion.from_ion` and `to_ion` read and write PartiQL-encoded Ion, including `$bag`,
`$missing` and `$ion`. `from_ion_data` boxes raw Ion;
`to_ion_data` preserves boxed Ion at every depth. Choose a matching pair:
a raw `$bag` annotation must stay boxed when reading Ion-preserving output.

`Value::from_ion` boxes raw Ion without decoding PartiQL annotations. It is
equivalent to `Value(ion_value)` or the codec's `from_ion_data`, and differs
from the codec's `from_ion` decoding operation.

Datagram readers return ordered arrays without implicit bag conversion.
`read_bytes` detects binary Ion by its version marker; otherwise it requires
valid UTF-8 text. `write_bytes` writes a binary datagram with a local symbol
table. `write_text` writes one value per line, with a final newline for
nonempty input and optional `pretty=true` layout.

```mbt check
test "binary datagram round trip" {
  let values = @partiql_ion.read_text("1 $missing::null $bag::[2, 3] $ion::foo")
  let bytes = @partiql_ion.write_bytes(values)
  @expect.expect(@partiql_ion.read_bytes(bytes)).to_equal(values)
}
```

Readers accept optional `catalog~` for shared symbol tables and `validation~`
for Ion Schema validation. Load a schema from text or binary bytes with
`load_schema_bytes`. `Validation::elements` validates each raw element;
`Validation::document` validates a complete datagram. Validation runs before
PartiQL decoding and collects violations with paths. Schemas describe physical
Ion types and annotations, including `$bag` and `$missing`.

```mbt check
test "validate raw Ion" {
  let schema = @partiql_ion.load_schema_bytes(
    b"$ion_schema_2_0 schema_header::{} type::{name: row, type: struct} schema_footer::{}",
  )
  let validation = @partiql_ion.Validation::elements(schema, "row")
  let values = @partiql_ion.read_text("{a: 1} {a: 2}", validation~)
  @expect.expect(values.length()).to_equal(2)
}
```

`CodecError` distinguishes malformed and unsupported encodings.
`IonDataError` distinguishes UTF-8, text/binary Ion, codec, schema and output
failures. `Violations` carries every validation path and message.

## Property tests

Import `moonrockz/partiql-value/arbitrary` and `moonbitlang/core/quickcheck`
for tests. `ArbValue`, `ArbIon` and `ArbTimestamp` implement generation and
shrinking. `gen_value(size, state)` accepts an explicit recursion budget;
nonpositive sizes produce leaves. Generators include absent values, numeric
boundaries, boxed Ion, maps and graphs.

See the [property testing guide](src/arbitrary/README.mbt.md) for a runnable
codec property and generator controls.

See the repository's [architecture](../../docs/architecture.md),
[Ion semantics](../../docs/adr/0005-ion-values-are-boxed.md) and
[datagram/session design](../../docs/adr/0007-ion-datagrams-and-sessions.md).
The checked examples above run through `mise run test:docs`.

## JSON documents

Import `moonrockz/partiql-value/json` as `@partiql_json`. `read_text` and
`read_bytes` read exactly one [RFC 8259](https://datatracker.ietf.org/doc/html/rfc8259)
JSON document. Bytes must be UTF-8 without a BOM. Empty input, concatenated
documents, JSON Lines, comments, trailing commas and Ion syntax are errors.
Strings must contain Unicode scalar values, so unpaired surrogate escapes
are rejected. Nesting is limited to 256 containers in both directions.

| JSON | PartiQL value |
|---|---|
| `null`, booleans, strings | `Null`, `Bool`, `String` |
| Integer without fraction or exponent | `Int` within Int64, otherwise `BigInt`; `-0` normalizes to `0` |
| Fraction or exponent, such as `1.2300` or `1e2` | Exact `Decimal`, preserving coefficient, scale and signed zero; `1e2` is coefficient 1, exponent 2 |
| Array | `List`, retaining order |
| Object | `Tuple`, retaining field order and duplicate names |

Decimal exponents, after adjustment for fractional digits, must fit Int32.
An explicit exponent must itself fit Int32. Large coefficients do not pass
through binary64, so neither integers nor decimals lose precision.

`write_text(value, pretty=false)` emits one document without a trailing newline.
`write_bytes` emits its UTF-8 bytes. `pretty=true` uses two-space indentation.
The writer emits duplicate fields, which other JSON readers may collapse.

| PartiQL value on write | JSON representation or error |
|---|---|
| `Null`, `Bool`, `String`, `Int`, `BigInt`, `List`, `Tuple` | Corresponding JSON value; nested values follow the same rules |
| `Decimal` | Exact coefficient and exponent, such as `12300e-4`; scale and negative zero survive read-back |
| Finite `Float` | Shortest binary64 round-trip number spelling; negative zero is `-0.0` |
| NaN or infinite `Float` | `JsonError::Unsupported` |
| `Missing`, `Bag`, `Map`, `Graph` | `JsonError::Unsupported` |
| `Date`, `Time`, `Timestamp`, `IntervalYM`, `IntervalDT` | `JsonError::Unsupported` |
| `Blob`, `Clob`, boxed `Ion` | `JsonError::Unsupported` |

JSON has no numeric type tags. Reading a written finite `Float` produces an
`Int` or `Decimal`, not a `Float`. Its spelling round-trips through a binary64
JSON consumer, but may denote a different exact decimal value from the binary
fraction. Use Ion when the numeric type or exact binary representation must
survive. Every value parsed by this JSON codec round-trips with structural
identity, including decimal scale and duplicate fields.

```mbt check
test "JSON document round trip" {
  let value = @partiql_json.read_text("{\"n\":9223372036854775808,\"price\":1.2300}")
  @expect.expect(@partiql_json.read_bytes(@partiql_json.write_bytes(value))).to_equal(value)
}
```

`JsonError` distinguishes invalid UTF-8, syntax errors with a zero-based
UTF-16 offset, unsupported output values, and invalid binding shapes.
`error.message()` gives a human-readable description. No unsupported value
is silently omitted or replaced with null. The `Tuple` constructor itself
removes `Missing` fields before the codec sees them.


## YAML input

`yaml.read_text(StringView)` and `read_bytes(BytesView)` return `Array[Value]`,
one value per document, in source order. Readers succeed with the whole stream
or raise `YamlError`; they never return partial documents. Empty or comment-only
input gives `[]`; an explicit empty document gives `[Null]`.

```mbt check
test "read exact YAML documents" {
  let values = @partiql_yaml.read_text("--- {price: 1.2300}\n--- {price: -0.00}")
  @expect.expect(values).to_equal(@partiql_ion.read_text("{price: 1.2300} {price: -0.00}"))
}
```

| YAML input | PartiQL value |
|---|---|
| Core null and booleans | Null and Bool |
| Decimal, `0o` octal and `0x` hexadecimal integers | Int64-backed Int, or BigInt when needed |
| Finite float spellings, including `1e2` | Exact Decimal with coefficient, exponent and negative zero preserved |
| `.inf`, `-.inf`, `.nan` and Core case variants | Float special values |
| Plain strings, quoted strings, literal/folded blocks | String |
| Sequences | List |
| Mappings | Tuple, preserving field order |

Resolution is YAML 1.2 Core: `yes`, `no`, `on`, `off`, dates, `0b10`, `1_000`
and `1:20` remain strings. `012` means twelve. Quoted/block text stays String
unless explicitly tagged. Versions other than 1.2 are rejected. Mapping keys
must resolve to String; quote a numeric-looking key or use `!!str`. Duplicate
decoded names are rejected by exact Unicode equality, including escaped and
aliased keys. No Unicode normalization is applied.

The seven core tags `!!str`, `!!null`, `!!bool`, `!!int`, `!!float`, `!!seq`
and `!!map` are supported, including full URIs and `%TAG` handles. Explicit
scalar tags require Core lexical forms and collection tags require the matching
node kind. `!!float '1'` produces Decimal; `!!float '-0'` retains negative zero.
Bare `!` forces the ordinary string/sequence/mapping kind. Unknown tags and
non-core timestamp, binary, set, omap, pairs and merge tags are unsupported.
Plain `<<` is an ordinary field name, with no merge expansion.

Anchors and acyclic aliases are supported. Each occurrence becomes an
independent value tree; changing a list cannot change another occurrence.
Forward/undefined aliases and cycles fail. Reused names refer to the latest
preceding anchor. Anchors and tag directives reset between documents. Comments,
styles and anchor names do not survive decoding. YAML output is not provided.

Bytes must be UTF-8; YAML BOMs are accepted. UTF-16 and UTF-32 are rejected.
`YamlError` distinguishes Encoding, Syntax, Unsupported, DuplicateKey, Limit and
Bindings. Positioned errors carry a 1-based document, line and Unicode-scalar
column relative to the supplied view, never a guessed byte offset.

Fixed limits apply per input stream: 256 nested containers, 1,000,000 expanded
nodes and 64 MiB of decoded scalar UTF-8 payload. Each scalar, sequence and
mapping is a node; mapping keys count as scalar nodes. Payload counts decoded
scalar spelling before type resolution, including keys, numeric spelling and
every alias copy. Empty scalars use zero bytes. Containers contribute no scalar
bytes. Anchor definitions count as their ordinary values, even if never aliased.
Alias expansion checks aggregate node/payload/depth costs before copying.
Decimal exponents must fit Int32 after the fractional scale is applied.

The parser also bounds scanner work to 6,000,016 token fetches, 256 flow levels,
512 indentation-stack entries and 64 MiB per metadata buffer. Scalar and folding
buffers are capped by the remaining scanned payload budget before growth.
These parser limits can reject unusually large presentation metadata even when
its eventual Value would be small. No materialized YAML/JSON intermediate or
binary64 numeric conversion is used. Coverage is a pinned, representative
[YAML fixture subset](src/yaml/fixtures/README.md), not a full-compliance claim.
