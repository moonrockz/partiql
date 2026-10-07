# moonrockz/partiql-eval

A PartiQL evaluator for MoonBit. It lowers a syntax tree to a plan and runs
the plan against global bindings, in permissive or strict typing mode.

```moonbit
let value = @eval.evaluate_text("[1, 'a']", env=@eval.Bindings::empty())
// value == List([Int(1), String("a")])
```

This version evaluates expressions: literals and collections. Queries,
operators and functions follow in later releases. Anything not supported yet
raises `EvalError::Unsupported`, never a wrong answer.
