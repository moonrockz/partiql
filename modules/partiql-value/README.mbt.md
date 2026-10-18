# moonrockz/partiql-value

The PartiQL data model for MoonBit, with the PartiQL-encoded Ion codec that
the [partiql-tests](https://github.com/partiql/partiql-tests) suite uses.

## Packages

| Package | Alias | Content |
|---|---|---|
| `moonrockz/partiql-value` | `@value` | `Value`, `Tuple`, `Bag`, `MapValue` (RFC 0104), `GraphValue` (RFC 0025), `Date`, `Time`, `Timestamp`, `IntervalYM`, `IntervalDT`, and the relations `==`, `sql_equals`, `eqg`, `compare` |
| `moonrockz/partiql-value/ion` | `@partiql_ion` | `from_ion`, `to_ion` (PartiQL-encoded Ion, as in partiql-tests); `from_ion_data`, `to_ion_data` (Ion-preserving: Ion data passes through exactly) |
| `moonrockz/partiql-value/arbitrary` | `@arbitrary` | quickcheck generators for property-based tests |

## Example

```moonbit
let bag = @value.Value::Bag(@value.Bag::new([@value.Value::Int(1L), @value.Value::Int(2L)]))
let same = @value.Value::Bag(@value.Bag::new([@value.Value::Int(2L), @value.Value::Int(1L)]))
@value.sql_equals(bag, same) // Bool(true): bags compare as multisets

// A tuple never holds MISSING: the constructor drops the pair.
let t = @value.Tuple::new([("a", @value.Value::Missing), ("b", @value.Value::Null)])
t.length() // 1

// Boxed Ion values compare by their lowered value: an Ion symbol equals a string.
let symbol = @value.Value::Ion(@ion_core.IonValue::symbol("hello"))
@value.sql_equals(symbol, @value.Value::String("hello")) // Bool(true)

// PartiQL-encoded Ion.
@partiql_ion.to_ion(bag) // $bag::[1, 2]
```

## Relations

| Relation | Use |
|---|---|
| `==` (`Eq`) | Structural identity: same case and contents; bags and tuples as multisets; decimal scale counts |
| `sql_equals` | The PartiQL `=` operator: MISSING beats NULL; numbers compare by value across types |
| `eqg` | Grouping equivalence: NULL eqg NULL, MISSING eqg MISSING, NaN eqg NaN |
| `compare` | The ORDER BY total order, with `NullsFirst` or `NullsLast` |

See `docs/architecture.md` and ADR 0005 in the repository.

## Ion datagrams

`moonrockz/partiql-value/ion` reads complete text and binary datagrams and
writes arrays of values in either format. These APIs use the same
PartiQL-encoded forms as `from_ion` and `to_ion`, including `$bag`, `$missing`
and `$ion`. `read_bytes` detects the binary version marker, otherwise
requiring valid UTF-8. `write_bytes` writes one binary datagram and its local
symbol table. `write_text` writes one value per line with an optional
`pretty=true` layout.

```moonbit
let values = @partiql_ion.read_text("1 $missing::null $bag::[2, 3] $ion::foo")
let bytes = @partiql_ion.write_bytes(values)
guard @partiql_ion.read_bytes(bytes) == values
```

The example runs in `src/ion/datagram_test.mbt`. Readers accept an optional
Ion `catalog~` and `validation~`. Load a schema with
`load_schema_bytes`, then construct `Validation::elements(schema, type_name)`
or `Validation::document(schema, type_name)`. Raw Ion is validated before
PartiQL decoding. Schema failures include every violation path. Schemas
describe physical Ion types and annotations, rather than lowered PartiQL
values. See [ADR 0007](../../docs/adr/0007-ion-datagrams-and-sessions.md).
