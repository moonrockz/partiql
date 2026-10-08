# moonrockz/partiql-eval

A PartiQL evaluator for MoonBit. It lowers a syntax tree to a logical plan and
interprets the plan against global bindings. It runs in permissive mode
(the default) or in strict mode.

```moonbit
let value = @eval.evaluate_text("1 + 2", env=@eval.Bindings::empty())
// value == Int(3)
```

A query runs against global bindings. `Bindings::of_ion` reads an Ion
struct, and each field becomes a global variable. `SELECT` with `WHERE` gives
a bag:

```moonbit
let value = @eval.evaluate_text(
  "SELECT VALUE x * 10 FROM [1, 2, 3] AS x WHERE x > 1",
  env=@eval.Bindings::empty(),
)
guard value == @value.Value::Bag(@value.Bag::new([Int(20), Int(30)]))
```

Pass `mode=@eval.Mode::Strict` to make a type error raise instead of giving
`MISSING`.

## What it evaluates

This version evaluates expressions: literals, collections, paths, arithmetic,
comparison, logic, `LIKE`, `BETWEEN`, `IN`, `IS`, `CASE`, `COALESCE`,
`NULLIF`, and datetime and interval arithmetic. It evaluates the core of a
query: `FROM` (collections, `AT`, `UNPIVOT`, joins), `LET`, `WHERE`,
`SELECT VALUE`, `SELECT` lists, `SELECT *`, `DISTINCT`, subqueries and
`VALUES`. `ORDER BY`, `LIMIT`, set operations, `PIVOT`, `WITH`, grouping,
functions and `CAST` follow in later releases. A form that is not supported yet raises
`EvalError::Unsupported`, never a wrong answer.

## Errors

- `TypeError`: an operand has the wrong type. Permissive mode gives `MISSING`;
  strict mode raises.
- `DataError`: the data is wrong (division by zero, Int64 overflow, an
  undefined variable). It raises in both modes.
- `Unsupported`: the form is not evaluated yet.
- `Syntax`: `evaluate_text` could not parse the text.
