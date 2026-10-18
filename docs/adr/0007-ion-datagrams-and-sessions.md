# 0007. Ion datagrams at the engine boundary

Status: Accepted

Ion input and output belong to the libraries. The CLI consumes the same APIs.
We retain PartiQL-encoded Ion semantics from ADR 0005, including `$bag`,
`$missing` and `$ion`, so existing text inputs keep their meaning.

## Codec and binding APIs

`partiql-value/ion` exposes `read_text(StringView)` and
`read_bytes(BytesView)` returning `Array[Value]`, and
`write_text(Array[Value], pretty~)` and `write_bytes(Array[Value])`.
Readers accept optional `catalog~` and `validation~` arguments. Bytes with
Ion's E0 01 00 EA version marker use the binary reader; other bytes are
strict UTF-8 Ion text. File extensions play no part. Writers build one
symbol table for the entire binary datagram. Imported shared symbols can
be resolved with an Ion `Catalog`. Known symbols are written locally. Boxed
Ion with unresolved shared symbols retains import metadata and needs the
same catalog when read back.

`IonDataError` distinguishes UTF-8, text parsing, binary parsing, PartiQL
codec, schema operation, schema violations and writing errors. It retains
upstream typed errors and all schema paths. CLI rendering happens only at
the CLI boundary. Existing `Bindings::of_ion` retains its EvalError contract.

`Bindings::from_ion_text` and `Bindings::from_ion_bytes` require exactly one
PartiQL tuple and expose its fields as globals. `Bindings::with_data` binds
a datagram by name, using the existing rule: zero elements become an empty
bag, one is used as-is, and many become a bag. These return new bindings.

## Sessions and element-wise evaluation

`Session::new` bundles bindings, mode, zone and optional clock. `evaluate`
and `evaluate_script` return values; `evaluate_ion_text` and
`evaluate_ion_bytes` encode script results. Free evaluation functions remain
available. Sessions do not mutate bindings during evaluation.

`Session::evaluate_each(source, name~, values~)` parses once and evaluates
one statement for each top-level element in order, rebinding `name` for
each call. Empty input produces no results. Scalars and encoded values
remain individual elements. This explicit operation avoids changing the
meaning of existing datagrams. Evaluation stops at the first failure.

## Schema validation

`Validation::elements(schema, type_name)` checks every raw Ion element,
collecting every violation with a top-level index in its path.
`Validation::document(schema, type_name)` uses Ion Schema's document
validation. Both run before PartiQL decoding and before evaluation. This
preserves annotations and distinguishes `$missing::null` from null and
`$bag::[...]` from an unannotated list. Schemas describe the physical Ion
encoding, not the lowered PartiQL type. Unknown types and invalid schemas
are errors, never successful validation.

## CLI

`--data` and `--env` read bytes through injected Io functions, including
stdin. `--each NAME` iterates the named `--data` datagram; other bindings
stay fixed. `--output-format ion|binary` defaults to Ion text. Binary
results form one datagram in input, element and statement order, with raw
bytes written to stdout. A statement failure retains earlier results as
a valid datagram and exits 1. `--compact` applies only to text output.

`--data-schema NAME=FILE` and `--env-schema FILE` load Ion Schema documents.
`--schema-type TYPE` selects the type, defaulting to `document`, and
`--schema-document` validates the whole datagram instead of each element.
Every binding must load and validate before any statement runs. Stdin
continues to have at most one reader, including schema input.

## Alternatives

Implicit per-element evaluation would break existing bag queries. Requiring
an input format or using file extensions would duplicate metadata and make
stdin awkward. Validating lowered values would discard annotations and
Ion types before checking them. Separate CLI codecs would leave embedders
to reproduce the same rules. Streaming and output shared-table configuration
are deferred; this API intentionally loads complete datagrams.

The CLI retains the free evaluation functions so it can render recovered
syntax diagnostics against each input's source and retain results before a
statement fails. The session methods return complete arrays or an error.
Both paths share the Ion transport, validation and binding APIs.
