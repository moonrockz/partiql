# 0006. Lower the syntax tree to a logical plan and interpret the plan

Date: 2026-10-07

Status: Accepted

## Context

M4 makes PartiQL statements run. The syntax tree is a poor input for an
evaluator:

- `SELECT` has many surface forms (`SELECT VALUE`, `SELECT *`, `PIVOT`, and
  others). The specification defines them by rewriting them to a core
  language.
- Names need resolution: a name is a global binding, a variable of an
  enclosing `FROM`, or an attribute of one of those variables.
- Later work needs static analysis (name checks, type inference). The
  analysis and the evaluator should read the same representation.
- The specification describes query evaluation as an algebra over binding
  tuples (`FROM` produces tuples, `WHERE` filters them, `SELECT` builds
  the result).

The two reference implementations follow this split. partiql-lang-kotlin
parses to an AST, plans it, and runs the plan. partiql-lang-rust does the
same with a logical plan.

## Decision

`moonrockz/partiql-eval` lowers the syntax tree to a logical plan and
interprets the plan. It does not interpret the syntax tree directly.

- The plan stays close to the specification's binding-tuple algebra, so each
  operator maps to a rule in the specification.
- `lower` desugars the surface forms and resolves names. It raises
  `EvalError::Unsupported`, with the span, for a form that the evaluator
  does not support yet.
- `interp` walks the plan and calls `ops` for the semantics of each
  operator. `ops` holds pure functions on values (arithmetic, comparison,
  logic, LIKE, datetime, paths) and does not know about the plan.
- M4a has scalar expressions only, so the plan has no relational operators
  yet. M4b adds them (scans, unnesting, joins, filters, projections, sorting,
  set operations, subqueries).
- Package layout of the module: `plan` (the plan and `EvalError`), `lower`
  (syntax tree to plan), `ops` (operator semantics), `interp` (the
  interpreter), and the root facade (`evaluate`, `evaluate_text`,
  `Bindings`).

## Consequences

- Each stage has its own tests. The operator laws evaluate PartiQL text
  with `evaluate_text`, so they test the parser, the lowering, the
  interpreter and `ops` together.
- Adding a surface form means changing `lower` only. Adding an operator
  means changing `plan`, `interp` and `ops`.
- Static analysis can later read the plan without running it.
- One extra step (lowering) costs a little time on each query. A plan can be
  built once and run many times.
- Name resolution moves to the lowering when queries arrive. Then an
  undefined name can become a lowering decision (see
  [conformance.md](../conformance.md)).
