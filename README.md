# partiql

A [MoonBit](https://www.moonbitlang.com) implementation of
[PartiQL](https://partiql.org), the SQL-compatible query language for nested
and semi-structured data.

The goal is compliance with the PartiQL specification. The
[partiql-tests](https://github.com/partiql/partiql-tests) conformance suite
measures that compliance.

## Status

The data model, the parser, the printer and the evaluator for expressions
are done. Queries are the next work. See [docs/roadmap.md](docs/roadmap.md) for the plan and
[docs/conformance.md](docs/conformance.md) for the current conformance
results.

## Modules

This repository is one MoonBit workspace with several modules. All modules
use the same version.

| Module | Purpose |
|---|---|
| [`moonrockz/partiql-value`](https://mooncakes.io/docs/moonrockz/partiql-value) | The PartiQL data model and its PartiQL-encoded Ion codec |
| [`moonrockz/partiql-syntax`](https://mooncakes.io/docs/moonrockz/partiql-syntax) | The PartiQL parser |
| [`moonrockz/partiql-eval`](https://mooncakes.io/docs/moonrockz/partiql-eval) | The PartiQL evaluator (expressions so far) |
| [`moonrockz/partiql`](https://mooncakes.io/docs/moonrockz/partiql) | The `partiql` command-line tool |
| `moonrockz/partiql-conformance` | The conformance harness (not published) |

See [docs/architecture.md](docs/architecture.md) for the module map and the
dependencies.

## Command-line tool

Run the tool from the registry with `moonx`:

```bash
moonx moonrockz/partiql --help
moonx moonrockz/partiql version
```

Native binaries for Linux, macOS and Windows are attached to each
[GitHub release](https://github.com/moonrockz/partiql/releases).

`query` accepts text and binary Ion for both `--data` and `--env`. The binary
version marker determines the format, including for stdin. Results default
to readable Ion text; `--output-format binary` writes a binary datagram.

```bash
partiql query --data t=rows.ion -e 'SELECT VALUE r.a FROM t AS r'
partiql query --data t=rows.ion --each t -e 't.a'
partiql query --data t=rows.ion --output-format binary -e 't' > result.10n
cat result.10n | partiql query --data t=- -e 't'
partiql query --data t=rows.ion --data-schema t=rows.isl --schema-type row -e 't'
```

Whole datagrams bind zero elements as an empty bag, one as-is, and many as a
bag. `--each t` instead runs the script once per element, in order. Empty
input runs no statements. `--env` requires one struct. Only one input may
read stdin. Failed statements exit 1 and retain earlier results, including
a valid binary datagram when binary output is selected.

`--data-schema NAME=FILE` validates a named binding; `--env-schema FILE`
validates every environment. `--schema-type TYPE` selects the schema type,
defaulting to `document`. `--schema-document` checks a whole datagram;
otherwise every element is checked separately. All validation runs before
any statement. Schemas describe raw PartiQL-encoded Ion, including `$bag`,
`$missing` and datetime annotations. Every violation is reported with its path.

## Library use

```bash
moon add moonrockz/partiql-value
```

Then import the package in `moon.pkg`. The module names contain hyphens, so
give each package an alias:

```
import {
  "moonrockz/partiql-value" @value,
  "moonrockz/partiql-value/ion" @partiql_ion,
}
```

## Development

The repository uses [mise](https://mise.jdx.dev) for tools and tasks.

```bash
mise install              # git-cliff, lefthook
mise run setup            # fetch the partiql-tests submodule and dependencies
mise run check            # format, lint, interfaces, tests, conformance
mise run hooks:install    # git hooks
bd bootstrap              # issue tracking (beads)
```

See [AGENTS.md](AGENTS.md) for the development rules.

## Specification

- PartiQL specification: <https://github.com/partiql/partiql-lang>
  ([v0.2.0 PDF](https://github.com/partiql/partiql-lang/releases/download/v0.2.0/PartiQL-Specification.pdf))
- Conformance suite: <https://github.com/partiql/partiql-tests>
- Reference implementations:
  [partiql-lang-kotlin](https://github.com/partiql/partiql-lang-kotlin),
  [partiql-lang-rust](https://github.com/partiql/partiql-lang-rust)

## License

[Apache-2.0](LICENSE)
