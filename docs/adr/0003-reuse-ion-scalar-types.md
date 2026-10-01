# 0003. Reuse the Ion scalar types of moonrockz/ion

Date: 2026-10-01

Status: Accepted

## Context

The PartiQL data model extends the Ion type system: PartiQL values include
Ion decimals, timestamps, symbols, blobs, clobs and s-expressions. The
`moonrockz/ion` module already implements these types (`Decimal`,
`Timestamp`, `SymbolToken`, `IonValue`) with their arithmetic and comparison.

partiql-lang-rust keeps Ion out of its core value crate and uses its own
decimal and date-time types.

## Decision

`moonrockz/partiql-value` imports `moonrockz/ion` and uses its scalar types in
the PartiQL `Value` type. Ion-typed data can embed an `IonValue`. The
PartiQL-encoded Ion codec is the `ion` package of the same module.

## Consequences

- No duplicate decimal or timestamp code.
- `moonrockz/ion` is a hard dependency of the data model. A user of
  `partiql-value` also gets `moonrockz/ion`.
- A bug or a missing feature in `moonrockz/ion` affects PartiQL. We report it
  to the ion repository.
