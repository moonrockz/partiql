# Ion Schema integration

The feasibility result for issue #40 and Beads `partiql-d6c.2` is go.
Validate raw Ion before decoding it as PartiQL. The implementation uses
`moonrockz/ion@0.6.0` and runs in the same portable codec package as the
text and binary readers.

## Library evidence

Ion 0.5.0 already supported Ion Schema 1.0 and 2.0, including document
constraints, annotations and schema imports. Ion 0.6.0 keeps those features
and makes schema loading, validation and regex compilation stack-safe.
Its schema operations accept optional fuel, defaulting to unlimited, and
validation can raise `IonError`. The integration catches those errors and
retains them in `IonDataError::Schema`.

The relevant upstream sources are
[`schema/load.mbt`](https://github.com/moonrockz/ion/blob/v0.6.0/pkgs/schema/load.mbt),
[`schema/validate.mbt`](https://github.com/moonrockz/ion/blob/v0.6.0/pkgs/schema/validate.mbt),
[`schema/document.mbt`](https://github.com/moonrockz/ion/blob/v0.6.0/pkgs/schema/document.mbt)
and [`schema/moon.pkg`](https://github.com/moonrockz/ion/blob/v0.6.0/pkgs/schema/moon.pkg).
`Schema::load` loads Ion values, `load_from_text` combines text parsing and
loading, and `validate` and `validate_document` return all violations.
`is_valid` is a convenience predicate that discards those details.
The schema package's production imports have no filesystem or target
restriction. Its internal stack-safe runner is portable.

## Encoding rules

A schema sees the physical Ion value before the PartiQL codec drops or
interprets annotations. In particular:

| PartiQL value | Physical schema shape |
|---|---|
| Bag | List with the `$bag` annotation |
| Missing | Null with the `$missing` annotation |
| Date | Canonical `$date` struct, or a legacy annotated timestamp |
| Interval | Struct with its PartiQL interval annotation and fields |
| Boxed Ion | Underlying Ion value with the `$ion` annotation |

A schema for an ordinary Ion list does not by itself require `$bag`.
An annotation constraint is needed to distinguish the encodings. A schema
for a PartiQL date string would be wrong: the codec supports a struct or
legacy timestamp. Decoding first would erase precisely the distinctions
that a schema may need to validate.

`Validation::elements(schema, type_name)` validates every top-level value,
collects all violations, and prefixes paths with the element index, such as
`$[1].a`. `Validation::document(schema, type_name)` validates the datagram
as an Ion Schema document, allowing document length and element constraints.
An empty datagram still resolves the schema type. Unknown types fail.
A malformed schema is a typed loading error, separate from data violations.

## Integration and verification

The library accepts a loaded schema in either validation mode. Schema imports
can use the resolver on `load_schema_bytes`. CLI schema files are self-contained;
unresolved imports produce loading errors. `--data-schema NAME=FILE` and
`--env-schema FILE` attach schemas, `--schema-type TYPE` chooses the named
type, and `--schema-document` chooses whole-datagram validation.

`modules/partiql-value/src/ion/datagram_test.mbt` checks text and binary
parity, all violation paths across several invalid elements, raw `$bag`,
`$missing` and `$date` annotations, document validation, and unknown types.
`modules/partiql/src/cli/ion_query_test.mbt` checks that invalid bindings
prevent evaluation and that the CLI reports every violation for both formats.
The tests run on wasm, wasm-gc, js and native through `mise run test:targets`.
No additional dependency is needed beyond the existing Ion module.

See [ADR 0007](adr/0007-ion-datagrams-and-sessions.md) for the API and CLI decisions.
