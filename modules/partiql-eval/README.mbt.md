# moonrockz/partiql-eval

A PartiQL evaluator for MoonBit. It lowers a syntax tree to a logical plan and
interprets the plan against global bindings. It runs in permissive mode
(the default) or in strict mode.

```moonbit
let value = @eval.evaluate_text("1 + 2", env=@eval.Bindings::empty())
// value == Int(3)
```

Pass `mode=@eval.Mode::Strict` to make a type error raise instead of giving
`MISSING`.

## What it evaluates

This version evaluates expressions: literals, collections, paths, arithmetic,
comparison, logic, `LIKE`, `BETWEEN`, `IN`, `IS`, `CASE`, `COALESCE`,
`NULLIF`, and datetime and interval arithmetic. Queries, functions and `CAST`
follow in later releases. A form that is not supported yet raises
`EvalError::Unsupported`, never a wrong answer.

## Errors

- `TypeError`: an operand has the wrong type. Permissive mode gives `MISSING`;
  strict mode raises.
- `DataError`: the data is wrong (division by zero, Int64 overflow, an
  undefined variable). It raises in both modes.
- `Unsupported`: the form is not evaluated yet.
- `Syntax`: `evaluate_text` could not parse the text.
