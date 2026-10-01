# 0001. Workspace monorepo with several modules

Date: 2026-10-01

Status: Accepted

## Context

The project will publish several MoonBit modules to mooncakes.io: the data
model, the parser, later the evaluator, and the `partiql` command-line tool.
The tool must run with `moonx moonrockz/partiql`. moonx runs the root package
of the module that the coordinate names, so the root package of
`moonrockz/partiql` must be the CLI executable.

Different users need different parts. A linter or a transpiler needs the
parser only. A data tool needs the data model only.

A package import path is the module name plus the package path. If a package
moves to a different module later, every user of that package breaks.

## Decision

Use one repository with one MoonBit workspace (`moon.work`). Each module is
one directory under `modules/`:

- `moonrockz/partiql-value`: data model and PartiQL-encoded Ion codec.
- `moonrockz/partiql-syntax`: parser.
- `moonrockz/partiql-eval`: reserved for the evaluator.
- `moonrockz/partiql`: the CLI. Its root package is the executable.
- `moonrockz/partiql-conformance`: the conformance harness, never published.

We verified with moon 0.1.20260920 that a workspace member resolves its
sibling modules locally, and that `moon package` builds a zip with only that
module and normal registry imports.

## Consequences

- Users depend only on the modules they need.
- The module boundaries are fixed now. A package never moves between modules.
- Each new module needs entries in the release tasks and in
  `docs/architecture.md`.
- The test data and the harness stay out of the published modules.
