# moonrockz/partiql-value

The PartiQL data model for MoonBit, with structural identity, SQL equality,
grouping equivalence, ordering and a PartiQL-encoded Ion codec.

## Installation and imports

```sh
moon add moonrockz/partiql-value
```

Add the packages you use to `moon.pkg`:

```mbt nocheck
import {
  "moonrockz/partiql-value" @value,
  "moonrockz/partiql-value/ion" @partiql_ion,
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
