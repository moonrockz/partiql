# moonrockz/partiql-eval

A PartiQL evaluator for MoonBit. It lowers a syntax tree to a logical plan and
interprets the plan against global bindings. It runs in permissive mode
(the default) or in strict mode.

```moonbit
let value = @eval.evaluate_text("1 + 2", env=@eval.Bindings::empty())
// value == Int(3)
```

A query gives a bag. This one has no global bindings:

```moonbit
let value = @eval.evaluate_text(
  "SELECT VALUE x * 10 FROM [1, 2, 3] AS x WHERE x > 1",
  env=@eval.Bindings::empty(),
)
guard value == @value.Value::Bag(@value.Bag::new([Int(20), Int(30)]))
```

`ORDER BY` gives a list, and `LIMIT` and `OFFSET` take a window of it:

```moonbit
let value = @eval.evaluate_text(
  "SELECT VALUE x FROM [3, 1, 2] AS x ORDER BY x DESC LIMIT 2",
  env=@eval.Bindings::empty(),
)
guard value == @value.Value::List([Int(3), Int(2)])
```

`GROUP BY` makes one row per group, and the aggregates fold each group:

```moonbit
let value = @eval.evaluate_text(
  "SELECT r, SUM(s.n) AS total FROM [{'r': 'a', 'n': 1}, {'r': 'a', 'n': 2}] AS s GROUP BY s.r AS r",
  env=@eval.Bindings::empty(),
)
guard value ==
  @value.Value::Bag(
    @value.Bag::new([
      Tuple(@value.Tuple::new([("r", String("a")), ("total", Int(3))])),
    ]),
  )
```

The built-in functions count Unicode code points and use full case mapping:

```moonbit
let value = @eval.evaluate_text(
  "UPPER(TRIM('  straße  '))",
  env=@eval.Bindings::empty(),
)
guard value == @value.Value::String("STRASSE")
```

`CAST` converts a value to a type. A text that is not a valid literal of the
type gives `MISSING` (a `TypeError` in strict mode); a value out of the range
of the type raises a `DataError` in both modes:

```moonbit
let value = @eval.evaluate_text(
  "CAST('3.14159' AS DECIMAL(4, 2))",
  env=@eval.Bindings::empty(),
)
guard value == @value.Value::Decimal(@ion.Decimal::parse("3.14"))
```

The datetime functions follow SQL where it defines them (EXTRACT, OVERLAPS)
and the PartiQL format patterns for TO_STRING and TO_TIMESTAMP:

```moonbit
let value = @eval.evaluate_text(
  "TO_STRING(DATE_ADD(day, 30, DATE '2024-02-15'), 'MMMM d, yyyy')",
  env=@eval.Bindings::empty(),
)
guard value == @value.Value::String("March 16, 2024")
```

The clock functions (`CURRENT_DATE`, `CURRENT_TIME`, `CURRENT_TIMESTAMP`,
`UTCNOW`) read a clock that you inject; the library never reads the wall
clock:

```moonbit
let clock = @eval.Clock::fixed(@time.date_time(2026, 10, 16, hour=9))
let value = @eval.evaluate_text(
  "CURRENT_DATE",
  env=@eval.Bindings::empty(),
  clock~,
)
guard value == @value.Value::Date(@value.Date::new(year=2026, month=10, day=16))
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
