# moonrockz/partiql-eval

A PartiQL evaluator for MoonBit. It lowers a syntax tree to a logical plan and
interprets the plan against global bindings. It runs in permissive mode
(the default) or in strict mode.

## Installation and imports

```sh
moon add moonrockz/partiql-eval
```

Add these imports to `moon.pkg` for the examples below:

```mbt nocheck
import {
  "moonrockz/partiql-eval" @eval,
  "moonrockz/partiql-value" @value,
  "moonrockz/partiql-value/ion" @partiql_ion,
  "moonrockz/ion/ion" @ion,
  "moonbitlang/x/time",
}
```

The checked examples use `moonrockz/expect` for assertions. Add it with
`moon add moonrockz/expect` and put this import in `moon.pkg` when copying
the test blocks:

```mbt nocheck
import { "moonrockz/expect" } for "test"
```

## Expressions and queries

```mbt check
test {
  let value = @eval.evaluate_text("1 + 2", env=@eval.Bindings::empty())
  @expect.expect(value).to_equal(@value.Value::Int(3))
}
```

A query gives a bag. This one has no global bindings:

```mbt check
test {
  let value = @eval.evaluate_text(
    "SELECT VALUE x * 10 FROM [1, 2, 3] AS x WHERE x > 1",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value == @value.Value::Bag(@value.Bag::Bag([Int(20), Int(30)]))).to_be_true()
}
```

`ORDER BY` gives a list, and `LIMIT` and `OFFSET` take a window of it:

```mbt check
test {
  let value = @eval.evaluate_text(
    "SELECT VALUE x FROM [3, 1, 2] AS x ORDER BY x DESC LIMIT 2",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value == @value.Value::List([Int(3), Int(2)])).to_be_true()
}
```

`GROUP BY` makes one row per group, and the aggregates fold each group:

```mbt check
test {
  let value = @eval.evaluate_text(
    "SELECT r, SUM(s.n) AS total FROM [{'r': 'a', 'n': 1}, {'r': 'a', 'n': 2}] AS s GROUP BY s.r AS r",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value ==
    @value.Value::Bag(
      @value.Bag::Bag([
        @value.Value::from_tuple(@value.Tuple([("r", String("a")), ("total", Int(3))])),
      ]),
    )).to_be_true()
}
```

The built-in functions count Unicode code points and use full case mapping:

```mbt check
test {
  let value = @eval.evaluate_text(
    "UPPER(TRIM('  straße  '))",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value == @value.Value::String("STRASSE")).to_be_true()
}
```

`CAST` converts a value to a type. A text that is not a valid literal of the
type gives `MISSING` (a `TypeError` in strict mode); a value out of the range
of the type raises a `DataError` in both modes:

```mbt check
test {
  let value = @eval.evaluate_text(
    "CAST('3.14159' AS DECIMAL(4, 2))",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value == @value.Value::Decimal(@ion.Decimal::parse("3.14"))).to_be_true()
}
```

The datetime functions follow SQL where it defines them (EXTRACT, OVERLAPS)
and the PartiQL format patterns for TO_STRING and TO_TIMESTAMP:

```mbt check
test {
  let value = @eval.evaluate_text(
    "TO_STRING(DATE_ADD(day, 30, DATE '2024-02-15'), 'MMMM d, yyyy')",
    env=@eval.Bindings::empty(),
  )
  @expect.expect(value == @value.Value::String("March 16, 2024")).to_be_true()
}
```

The clock functions (`CURRENT_DATE`, `CURRENT_TIME`, `CURRENT_TIMESTAMP`,
`UTCNOW`) read a clock that you inject; the library never reads the wall
clock:

```mbt check
test {
  let clock = @eval.Clock::fixed(@time.date_time(2026, 10, 16, hour=9))
  let value = @eval.evaluate_text(
    "CURRENT_DATE",
    env=@eval.Bindings::empty(),
    clock~,
  )
  @expect.expect(value == @value.Value::Date(@value.Date::Date(year=2026, month=10, day=16))).to_be_true()
}
```

Pass `mode=@eval.Mode::Strict` to make a type error raise instead of giving
`MISSING`.

## What it evaluates

This version evaluates expressions: literals, collections, paths, arithmetic,
comparison, logic, `LIKE`, `BETWEEN`, `IN`, `IS`, `CASE`, `COALESCE`,
`NULLIF`, and datetime and interval arithmetic. It evaluates the core of a
query: `FROM` (collections, `AT`, `UNPIVOT`, joins), `LET`, `WHERE`,
`SELECT VALUE`, `SELECT` lists, `SELECT *`, `DISTINCT`, subqueries and
`VALUES`. It also evaluates `ORDER BY`, `LIMIT` and `OFFSET`, the set
operations (`UNION`, `INTERSECT` and `EXCEPT`, with `ALL`, `OUTER` and
`CORRESPONDING`), `PIVOT`, `TABLE` and `WITH`, and grouping: `GROUP BY`,
`GROUP AS`, `GROUP ALL`, `HAVING`, the SQL aggregates (`COUNT`, `SUM`, `AVG`,
`MIN`, `MAX`, `ANY`, `SOME`, `EVERY`) and the `COLL_` functions. It
evaluates the built-in functions `CHAR_LENGTH`, `OCTET_LENGTH`, `BIT_LENGTH`,
`UPPER`, `LOWER`, `TRIM`, `SUBSTRING`, `POSITION`, `OVERLAY`, `TEXT_REPLACE`,
`ABS`, `MOD`, `SIZE`, `CARDINALITY`, `EXISTS`, `TUPLEUNION` and the `MAP_`
functions. It evaluates `CAST` to every type except `SEXP` and `ARRAY<T>`;
`evaluate` takes the session time zone of `CAST` as `zone~` (default UTC).
It evaluates the datetime functions `EXTRACT`, `DATE_ADD`, `DATE_DIFF`,
`OVERLAPS`, `TO_STRING` and `TO_TIMESTAMP`, and the clock functions
`CURRENT_DATE`, `CURRENT_TIME`, `CURRENT_TIMESTAMP` and `UTCNOW` (with an
injected `clock~`). A form that is not
supported yet raises `EvalError::Unsupported`, never a wrong answer.

## Errors

- `TypeError`: an operand has the wrong type. Permissive mode gives `MISSING`;
  strict mode raises.
- `DataError`: the data is wrong (division by zero, Int64 overflow, an
  undefined variable), or the statement is wrong before any data is read
  (an unknown function name, a CAST to NULL). It raises in both modes.
- `Unsupported`: the form is not evaluated yet.
- `Syntax`: `evaluate_text` could not parse the text.

## Ion sessions

Import `moonrockz/partiql-value/ion` as `@partiql_ion`. An Ion datagram is
an ordered array of top-level values. The readers accept text or bytes;
`read_bytes` detects binary Ion by its version marker and otherwise reads
strict UTF-8 text. `IonDataError` keeps text, binary, encoding, schema and
PartiQL codec failures distinct.

This example reads a binary environment, evaluates a script and writes binary results:

```mbt check
test {
  let input = @partiql_ion.write_bytes(@partiql_ion.read_text("{a: 2, b: $bag::[1, 3]}"))
  let session = @eval.Session::Session(env=@eval.Bindings::from_ion_bytes(input))
  let output = session.evaluate_ion_bytes("a + 1; SELECT VALUE x * a FROM b AS x")
  @expect.expect(@partiql_ion.read_bytes(output)).to_equal(@partiql_ion.read_text("3 $bag::[2, 6]"))
}
```

`Bindings::from_ion_text` and `from_ion_bytes` require exactly one struct.
For named data, use `Bindings::empty().with_data("t", values)`: no elements
bind an empty bag, one binds as-is, and many bind a bag. For document-by-document
execution, `session.evaluate_each("t.a", name="t", values~)` returns one
result per element, in order. Empty input returns no results. Session bindings
are unchanged, including after a failure.

`Session(...)` accepts `env~`, `mode~`, `zone~` and `clock~` with the same
defaults as `evaluate`. `evaluate_script` parses the whole script before
running any statement. `evaluate_ion_text` and `evaluate_ion_bytes` return
one datagram for all script results, or raise `SessionError::Evaluation`
or `SessionError::Ion`. Statements stop at the first error. Sessions keep
no partial results; the CLI retains results preceding a failing statement.

For schema validation, pass `validation~` to an Ion reader or binding
constructor. Build it with `Validation::elements(schema, "row")` for
per-element validation or `Validation::document(schema, "rows")` for a
whole-datagram schema. Validation checks raw Ion before PartiQL decoding,
collects every violation and retains its path. A schema must describe the
physical PartiQL encoding, including annotations such as `$bag` and
`$missing`. Readers also accept `catalog~` for shared symbol imports.

## Package boundaries and reuse

| Package | Purpose |
|---|---|
| `moonrockz/partiql-eval` | `evaluate`, `evaluate_text`, `Bindings`, `Session`; re-exported mode, errors, clock and zone types |
| `moonrockz/partiql-eval/plan` | Lowered expression and relation ADTs with source spans |
| `moonrockz/partiql-eval/lower` | AST-to-plan validation and name resolution |
| `moonrockz/partiql-eval/ops` | Pure value operators, casts, functions and clock abstraction |
| `moonrockz/partiql-eval/interp` | Plan execution with a fresh context per statement |

Use the root package for ordinary evaluation. Parse once with
`@syntax.parse`, then call `evaluate(statement, env~)` for different
bindings. Lower and interpret plans directly only when your application needs
to manage those steps. Operator functions raise `OpFailure`; the interpreter
attaches source spans and applies permissive/strict mode.

`Bindings::of_pairs` copies its input and preserves MISSING bindings and
repeated names. `Bindings::of_tuple` uses the tuple's retained fields.
Unquoted lookup ignores ASCII case; quoted names match exactly. Duplicate
matches raise an ambiguity error when referenced. `with_value` returns a new
environment in which the exact name replaces earlier bindings of that name.

```mbt check
test "reusable session" {
  let env = @eval.Bindings::of_pairs([("x", @value.Value(4))])
  let session = @eval.Session(env~, mode=@eval.Mode::Strict)
  @expect.expect(session.evaluate_script("x + 1; x * 2")).to_equal([@value.Value(5), @value.Value(8)])
}
```

Construct sessions with `Session(...)`; `Session::new` is a deprecated alias.
`ZoneOffset::from_minutes` returns `None` for offsets outside -18:00..+18:00;
`ZoneOffset::utc()` supplies UTC. Clock reads can fail and are translated to
`DataError`. Each statement samples its clock on first use and reuses that
instant for every clock function within the statement.

All checked examples run through `mise run test:docs`. See the repository's
[architecture](../../docs/architecture.md) and
[conformance report](../../docs/conformance.md) for supported syntax and behavior.
