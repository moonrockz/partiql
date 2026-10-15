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
`MIN`, `MAX`, `ANY`, `SOME`, `EVERY`) and the `COLL_` functions. Functions
and `CAST` follow in later releases. A form that is not supported yet raises
`EvalError::Unsupported`, never a wrong answer.

## Errors

- `TypeError`: an operand has the wrong type. Permissive mode gives `MISSING`;
  strict mode raises.
- `DataError`: the data is wrong (division by zero, Int64 overflow, an
  undefined variable). It raises in both modes.
- `Unsupported`: the form is not evaluated yet.
- `Syntax`: `evaluate_text` could not parse the text.
