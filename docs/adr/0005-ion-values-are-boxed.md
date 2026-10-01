# 0005. Ion values are a boxed representation, lowered for semantics

Date: 2026-10-01

Status: Accepted

## Context

The PartiQL data model "extends SQL to Ion's type system" (`model.adoc`), but
the specification does not name SYMBOL or SEXP as types, does not mention typed
nulls or annotations, and does not say that output must keep Ion details. The
reference implementations differ:

- partiql-lang-kotlin v0.x had first-class SYMBOL and SEXP types. Version 1
  removed them and keeps exact Ion in an `IonVariant` datum, which it lowers
  (symbol → string, sexp → array, typed null → NULL) for every semantic and
  writes back exactly.
- partiql-lang-rust keeps exact Ion in `Value::Variant` for backtick literals
  and `$ion::` values. Its equality is not consistent inside collections:
  `` [`hello`] = ['hello'] `` is false.

The partiql-tests corpus has 24 evaluation tests that expect `$ion::`
pass-through (for example `null.int` gives `$ion::null.int`). Elsewhere, Ion
symbols in test data act as strings (246 values).

Ion interop is a goal of this project: a query over Ion data should be able to
pass values through without loss.

## Decision

`Value` has one case, `Ion(IonValue)`, that holds an exact Ion value. It is a
representation, never a PartiQL type.

- `Value::lower` converts it to a core value: symbol → `String`, sexp → `List`,
  typed null → `Null`, annotations dropped, an Ion timestamp → `Timestamp` with
  time zone (an unknown offset becomes UTC).
- `sql_equals`, `eqg` and `compare` act on lowered values. So symbol = string,
  sexp = list, and clob = blob when the octets are equal.
- Structural identity (`Eq`) is the only relation that sees the `Ion` case
  directly; it uses Ion equality.
- The PartiQL-encoded codec (`from_ion`, `to_ion`) reads `$ion::x` as
  `Ion(x)` and writes it back.
- The Ion-preserving codec mode (`from_ion_data`, `to_ion_data`) is for Ion
  data: decoding boxes the value, and encoding writes every boxed Ion value,
  at any depth, exactly as it was read. Computed values that Ion cannot
  express use the PartiQL-encoded `$` forms.

## Consequences

- Values that a query passes through can keep every Ion detail.
- Every relation lowers first, so no new type rules are needed for symbols,
  sexps or typed nulls.
- No SYMBOL or SEXP type names, `IS` predicates or CAST targets exist. If they
  are needed later, they go into an extension.
- Adding the case now is cheap. Adding it later would break every exhaustive
  `match` over `Value`.
