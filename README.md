# partiql

A [MoonBit](https://www.moonbitlang.com) implementation of
[PartiQL](https://partiql.org), the SQL-compatible query language for nested
and semi-structured data.

The goal is compliance with the PartiQL specification. The
[partiql-tests](https://github.com/partiql/partiql-tests) conformance suite
measures that compliance.

## Status

The implementation includes the data model, parser, printer, query evaluator,
aggregates, casts, datetime functions, Ion sessions, strict JSON input/output and YAML input. Some specification
forms remain unsupported. See [docs/roadmap.md](docs/roadmap.md) for the plan and
[docs/conformance.md](docs/conformance.md) for the current conformance
results.

## Modules

This repository is one MoonBit workspace with several modules. All modules
use the same version.

| Module | Purpose |
|---|---|
| [`moonrockz/partiql-value`](https://mooncakes.io/docs/moonrockz/partiql-value) | The PartiQL data model with Ion, JSON and YAML codecs |
| [`moonrockz/partiql-syntax`](https://mooncakes.io/docs/moonrockz/partiql-syntax) | The PartiQL parser |
| [`moonrockz/partiql-eval`](https://mooncakes.io/docs/moonrockz/partiql-eval) | The PartiQL query evaluator |
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

### JSON

Use `--input-format json` for one strict JSON document per `--data` or `--env`
file, including stdin. Objects become tuples, arrays become lists, and
numbers retain integer precision or exact decimal scale. Duplicate keys
survive. `--env` requires an object. `--each t` iterates a JSON array.

```sh
partiql query --input-format json --data t=rows.json --output-format json \
  -e 'CAST((SELECT VALUE r.a FROM t AS r) AS LIST)'
```

`--output-format json` writes one document per result; add `--compact` for
JSON Lines. Input accepts one document, not JSON Lines. JSON output rejects
bags, MISSING, non-finite floats, maps, graphs, temporals, intervals, blobs,
clobs and boxed Ion. Finite floats write binary64 round-trip spellings and
read back as Int/Decimal. Use an explicit list cast for SELECT bags. See
[the complete mapping, errors and limits](modules/partiql-value/README.mbt.md#json-documents)
and [CLI examples](modules/partiql/README.mbt.md#json-input-and-output).
Ion remains the default; Ion Schema options require Ion input.

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

The library guides include imports, checked examples and error contracts:

- [Values, Ion, JSON and YAML](modules/partiql-value/README.mbt.md)
- [Parsing, formatting and diagnostics](modules/partiql-syntax/README.mbt.md)
- [Evaluation, bindings and sessions](modules/partiql-eval/README.mbt.md)
- [CLI commands and embedding](modules/partiql/README.mbt.md)

For evaluation, add `moonrockz/partiql-eval` and import it as `@eval`, with
`moonrockz/partiql-value` as `@value`. This test uses `moonrockz/expect`:

```mbt check
test "library query" {
  let session = @eval.Session()
  let result = session.evaluate("SELECT VALUE x * 2 FROM [1, 2, 3] AS x")
  let expected = @value.Value::from_bag(@value.Bag([
    @value.Value(2), @value.Value(4), @value.Value(6),
  ]))
  @expect.expect(result).to_equal(expected)
}
```

Construct domain types with `Type(...)` and convert supported MoonBit values
with `Value(x)`. Typed `Value::from_*` methods wrap known payload types and
resolve nested domain constructors, such as
`Value::from_bag(@value.Bag(items))`. Enum variants remain available for patterns.
`Type::Type(...)` selects a standalone constructor when an enum variant
shares its name. Former `new` factories remain deprecated aliases; the
fallible offset factory is now `ZoneOffset::from_minutes`.

## Development

The repository uses [mise](https://mise.jdx.dev) for tools and tasks.

```bash
mise install              # git-cliff, lefthook
mise run setup            # fetch the partiql-tests submodule and dependencies
mise run check            # format, lint, interfaces, docs, tests, conformance
mise run test:docs        # compile and run README examples
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


### YAML input

Query YAML files or UTF-8 stdin with `--input-format yaml`:

```sh
partiql query --input-format yaml --data t=manifest.yaml --each t -e 't.name'
```

The codec supports YAML 1.2 Core values, exact finite numbers, core tags,
document streams and bounded aliases. Keys must be strings and duplicate keys
are rejected. Empty streams contain no values; explicit empty documents contain
Null. YAML is input-only; results use Ion, binary Ion or JSON. See the
[value mapping and limits](modules/partiql-value/README.mbt.md#yaml-input) and
[CLI examples](modules/partiql/README.mbt.md#yaml-input).
