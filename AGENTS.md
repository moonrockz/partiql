# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Overview

This repository is a MoonBit implementation of [PartiQL](https://partiql.org),
the SQL-compatible query language for nested and semi-structured data. The goal
is **compliance with the PartiQL specification**, measured with the
[partiql-tests](https://github.com/partiql/partiql-tests) conformance suite.

References:

- Specification (source of truth): <https://github.com/partiql/partiql-lang>
  (AsciiDoc in `src/`, RFCs in `RFCs/`). The old `partiql/partiql-spec`
  repository is archived.
- De facto grammar: `partiql-lang-kotlin`
  `partiql-parser/src/main/antlr/PartiQLParser.g4` and `PartiQLTokens.g4`.
  The specification has only EBNF fragments.
- Conformance suite: <https://github.com/partiql/partiql-tests>, a git submodule
  at `modules/partiql-conformance/partiql-tests`.
- Reference implementations: partiql-lang-kotlin, partiql-lang-rust.

### Architecture Summary

```
moon.work                         # workspace: one module per directory in modules/
modules/
├── partiql-value/                # moonrockz/partiql-value
│   └── src/                      # Value: the PartiQL data model
│       └── ion/                  # PartiQL-encoded Ion codec (from_ion, to_ion)
├── partiql-syntax/               # moonrockz/partiql-syntax
│   └── src/                      # parse; M2 adds lexer, AST and parser packages
├── partiql/                      # moonrockz/partiql: the CLI (moonx moonrockz/partiql)
│   └── src/                      # executable entry point
│       └── cli/                  # the command line as a library (run -> Outcome)
└── partiql-conformance/          # never published
    ├── partiql-tests/            # git submodule (pinned commit)
    ├── baseline/                 # ratchet baseline: passing test ids per check
    └── src/                      # test-only harness
docs/                             # architecture, roadmap, conformance, ADRs
mise-tasks/                       # file-based mise tasks
.dev/                             # gitignored working area (specs, plans, scratch)
.beads/                           # issue tracking
```

See `docs/architecture.md` for the module map, and `docs/adr/` for the
decisions that shape the repository.

## Library Dependencies

### MoonBit Core Library

Treat these three official `moonbitlang` modules together as the MoonBit core
library. Look in them first before you write a helper or add a third-party
dependency.

| Module | Purpose |
|--------|---------|
| `moonbitlang/core` | Standard library that ships with the toolchain (builtin, debug, collections, strings, argparse, etc.) |
| [`moonbitlang/x`](https://mooncakes.io/docs/moonbitlang/x) | Official standard library extensions (fs, sys, path, time, codec, encoding, etc.) |
| [`moonbitlang/async`](https://mooncakes.io/docs/moonbitlang/async) | Official async runtime (tasks, I/O, process, HTTP); native target preferred |

`moonbitlang/core` comes with the toolchain. `moonbitlang/x` and
`moonbitlang/async` are versioned on mooncakes.io, so keep them on the latest
release when you bump the toolchain.

### Third-Party Dependencies

| Module | Purpose |
|--------|---------|
| [moonrockz/ion](https://mooncakes.io/docs/moonrockz/ion) | Ion data model and text reader. `partiql-value` uses its `IonValue`, `Decimal`, `Timestamp` and `SymbolToken` (see ADR 0003). |
| [moonrockz/expect](https://mooncakes.io/docs/moonrockz/expect) | Fluent test assertions |

Module dependencies are declared in the `import` block of each module's
`moon.mod`. Each package lists what it uses in its `moon.pkg`. Use
`import { ... } for "test"` or `for "wbtest"` for test-only dependencies.

### Toolchain

- Supported targets: wasm, wasm-gc, js and native. Library modules
  (`partiql-value`, `partiql-syntax`) must build and pass their tests on all
  four (`mise run test:targets`, CI job `unit`).
- Library code imports only `moonbitlang/core` and `moonrockz/ion`.
  `moonbitlang/x` belongs in the CLI and in test-only code.
- The CLI executable supports native and wasm only: on js, `@env.args()`
  starts with the node binary. The conformance harness supports native and js
  (`moonbitlang/x/fs`).
- The MoonBit toolchain version is pinned in `.github/workflows/*.yml`
  (`MOONBIT_VERSION`). Keep your local toolchain on the same version
  (`moon version --all`, `moon upgrade`).
- To upgrade: run `moon upgrade`, bump `MOONBIT_VERSION`, bump the `import`
  versions in each `moon.mod`, then run `moon update && mise run check`. Fix
  all new warnings, not only errors: `mise run lint:check` uses `--deny-warn`.
- Use `derive(Debug)` (not `derive(Show)`) for data types. In string
  interpolation, use `@debug.to_string(x)` for values that have only `Debug`.
- `try?` is deprecated. Use `try expr catch { ... } noraise { ... }`.

## Project Structure

- MoonBit packages are organized per directory; each has a `moon.pkg` listing
  dependencies.
- Blackbox tests: `*_test.mbt`; whitebox tests: `*_wbtest.mbt`.
- Module names contain hyphens. A blackbox test imports its own package with
  an explicit alias, for example
  `import { "moonrockz/partiql-value" @value } for "test"`.
- Each module has a `moon.mod` (the legacy `moon.mod.json` format is
  deprecated) with `warnings = "-implicit_impl_as_method"`.

## Design Philosophy

This project follows **functional design principles** (aligned with the other
moonrockz libraries):

- **Algebraic data types (ADTs)** for domain concepts (enums + structs).
- **Make invalid states unrepresentable** — use the type system to prevent
  illegal states.
- **Avoid primitive obsession** — use domain types instead of raw strings and
  ints.
- **Prefer immutability** — minimal `mut`; favor returning new values.
- **Pattern matching over conditionals** — exhaustive `match` on enums.
- **Total functions** — use `Option`/`Result` or typed `raise` for failures;
  avoid panic.
- **No sentinel values** — absence is `T?` or an enum variant, never `""`, `0`
  or `-1`.

## Test-Driven Development (TDD)

- **Red–Green–Refactor**: write a failing test first, watch it fail, then
  write the minimal implementation, then refactor.
- Use `#declaration_only` to sketch public APIs before implementation.
- Write assertions with [moonrockz/expect](https://mooncakes.io/docs/moonrockz/expect):
  `@expect.expect(actual).to_equal(expected)`, `.to_be_true()`,
  `.to_contain(...)`. Use `inspect(...)` for snapshot tests.
- Run `mise run test:unit` for tests; `moon test --update` to refresh
  snapshots. Read every snapshot change before you commit it.

## Coding Convention

- MoonBit block style: blocks separated by `///|`; block order irrelevant.
- Deprecated code in `deprecated.mbt` per directory.

## Conventional Commits

All commits MUST use **[Conventional Commits](https://www.conventionalcommits.org)**:

```
type(scope): description
```

Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`,
`chore`, `style`. Breaking changes: add `!` after type (for example
`feat(syntax)!: change the AST`).

Scopes: `value`, `syntax`, `cli`, `conformance`, `ci`, `build`, `docs`.

## Workspace and Modules

- `moon.work` lists the member modules. Each module is one directory under
  `modules/`, with the same name as the module short name.
- All modules share one version (lockstep, ADR 0002).
- Never move a package from one module to another: the import path changes
  and every user breaks. Choose the module when you create the package.
- A new module needs: `moon work use modules/<name>`, a `LICENSE` symlink
  (`ln -s ../../LICENSE LICENSE`), an entry in `mise-tasks/release/publish`
  (in dependency order), `release/bump` and `release/check-version`, and a
  row in `docs/architecture.md`.

## CLI

The `partiql` tool parses arguments with `moonbitlang/core/argparse`. argparse
has gaps; the `cli` package fills them:

| Gap in `moonbitlang/core/argparse` | Supplement in `cli` |
|---|---|
| Built-in `--help`, `--version` and `help` write to the process stdout and exit the process | Built-ins disabled; own `-h/--help` (global) and `-V/--version` flags; own `help [command]` command; `run` returns an `Outcome` |
| `<command> -h` fails when the command has a required positional, because validation runs before help is seen | `help_request` scans the arguments for `-h`/`--help` (before `--`) and answers help before argparse parses |
| `render_help` of a command built alone prints `Usage: version`, without `partiql` | `command(name, prefix)` builds help commands with the name `"partiql <name>"` |
| A parse error holds the full help text | `short_error` keeps the error line and the usage line, and adds a hint |
| No examples or epilog section | `help_text` appends an `Examples:` block per command |

Rules:

- `run` never writes to the process streams. Only `src/main.mbt` prints and
  exits.
- Exit status: 0 for success, 2 for a usage error.
- Every new command gets an entry in `command_names`, `command` and
  `examples`, a help test and a usage-error test.

## Mise Tasks

Tasks are file-based scripts in `mise-tasks/`. Never add inline `[tasks]` to
`.mise.toml`. GitHub workflows call `mise run <task>`.

| Task | Purpose |
|---|---|
| `setup` | Fetch the submodule and MoonBit dependencies |
| `check` | All local gates: format, lint, interfaces, tests, conformance |
| `lint:fmt` | Fail if `moon fmt` would change a file |
| `lint:check` | `moon check --deny-warn` |
| `lint:info` | Fail if the `.mbti` interfaces are out of date |
| `test:unit` | All workspace tests (`--target <t>` for one target) |
| `test:targets` | All workspace tests on wasm, wasm-gc, js and native |
| `test:conformance` | partiql-tests against the ratchet baseline |
| `conformance:ratchet` | Rewrite the conformance baseline from the current results |
| `build:cli` | Build the CLI for wasm and native (release mode) |
| `hooks:install` | Install the lefthook git hooks |
| `release:version` | Next version from conventional commits |
| `release:bump` | Set every module version, sibling import and the CLI version |
| `release:check-version` | Fail unless all versions equal the given version |
| `release:changelog` | Generate `CHANGELOG.md` with git-cliff |
| `release:notes` | Release notes for the release at HEAD |
| `release:credentials` | Write mooncakes.io credentials from `MOONCAKES_USER_TOKEN` |
| `release:publish` | Publish the modules in dependency order |
| `release:prepare-assets` | Collect the CLI binaries for the GitHub release |

## Conformance

`modules/partiql-conformance` runs partiql-tests with three checks:
`syntax` (SyntaxSuccess and SyntaxFail cases), `eval-parse` (every evaluation
statement must parse) and `codec` (every `env` and `output` value must
round-trip through the PartiQL-encoded Ion codec). See `docs/conformance.md`.

Rules:

- Never edit `baseline/*.txt` by hand. Run `mise run conformance:ratchet` and
  commit the baseline in the same commit as the change that made tests pass.
  CI fails when the baseline is out of date.
- A regression (a baseline id that fails) is a bug. Fix it. Do not remove the
  id.
- `ParseError::Unsupported` and `CodecError::Unsupported` always count as
  failures, never as expected errors.
- To bump the submodule pin, follow `docs/conformance.md`.

## Tooling

- `moon fmt` — format code.
- `moon info` — update generated `.mbti` interfaces.
- `moon check` — typecheck.
- Run `moon info && moon fmt` before committing when API or formatting may
  have changed.

## The `.dev/` Working Area

`.dev/` is a gitignored scratch area for AI-assisted development: temporary
scripts, agent and script outputs, and working documents. Nothing in it is
committed. Layout:

- Specs from the superpowers `brainstorming` skill:
  `.dev/docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`
- Plans from the superpowers `writing-plans` skill:
  `.dev/docs/superpowers/plans/YYYY-MM-DD-<topic>-plan.md`
- Scratch scripts and their outputs: `.dev/scripts/`, `.dev/out/`

This layout overrides the default location of any skill or tool. Never place
specs, plans or other working documents under `docs/`, and never `git add`
anything under `.dev/`. Decisions with lasting effect go to `docs/adr/` as a
new ADR.

## Release Process

- Publishes to **mooncakes.io** and **GitHub Releases**.
- Prepare: `mise run release:bump`, `mise run release:changelog`, commit.
- Trigger: push tag `v*`, or run the Release workflow (workflow_dispatch) on
  `main`.
- Publish order: `partiql-value`, `partiql-syntax`, `partiql`.
  `partiql-conformance` is never published.
- Requires the `MOONCAKES_USER_TOKEN` org secret.
- Tags and releases are **immutable**. Publish to mooncakes.io first, then
  create the GitHub release.

## Landing the Plane (Session Completion)

When ending a work session:

1. File issues for remaining work.
2. Run quality gates (`mise run check`) if code changed.
3. Update issue status (e.g. `bd close` / `bd update`).
4. **PUSH TO REMOTE** — mandatory: `bd sync`, then `git pull --rebase` and
   `git push`. Work is not complete until both pushes succeed.
5. Clean up; verify all changes committed and pushed; hand off context for
   next session.
