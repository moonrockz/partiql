# moonrockz/partiql

The `partiql` command-line tool.

```bash
moonx moonrockz/partiql --help
moonx moonrockz/partiql version
moonx moonrockz/partiql format query.sql           # print PartiQL laid out at width 80
moonx moonrockz/partiql format --width 100 q.sql   # another line width
moonx moonrockz/partiql format --compact q.sql     # one line per statement
moonx moonrockz/partiql format --write *.sql       # rewrite files in place
moonx moonrockz/partiql format -e 'select a from t'
cat query.sql | moonx moonrockz/partiql format     # read stdin
moonx moonrockz/partiql check *.sql                # report every parse error
moonx moonrockz/partiql parse -e 'select a from t' # print the syntax tree
moonx moonrockz/partiql query -e 'select value x * 2 from <<1, 2>> as x'
moonx moonrockz/partiql query --data t=rows.ion -e 'select a from t where b > 1'
moonx moonrockz/partiql query --env env.ion query.sql
cat rows.ion | moonx moonrockz/partiql query --data t=- query.sql
```

`format` keeps comments. Each parse error prints a rendered diagnostic (the
location, the source line and a marker); every error of an input is
reported, and the exit status is 1. `format` leaves an input with errors
unchanged. Colour:
`--color=auto|always|never` (auto: on when stderr is a terminal and `NO_COLOR`
is unset).

`query` evaluates PartiQL statements and prints each result as
PartiQL-encoded Ion (`$bag::[...]`, `$missing::null`). Global bindings come
from Ion files by default:

- `--env FILE` reads one Ion struct; each field is a global.
- `--data NAME=FILE` binds the global `NAME`. A file with one top-level
  value binds that value; a file with zero or several values binds a bag of
  them.
- Only one input can read stdin (`-`).
- `--strict` evaluates in strict mode; `--compact` prints each result on one
  line.
- An evaluation error prints a rendered diagnostic at its position. Exit
  status: 0 for success, 1 when an input cannot be read or parsed or a
  statement fails, 2 for a usage error.

Native binaries for Linux, macOS and Windows are attached to each
[GitHub release](https://github.com/moonrockz/partiql/releases).

## Ion datagrams and schemas

`--data` and `--env` accept binary Ion or UTF-8 text. The binary version marker
determines the format, including for stdin. `--env` requires exactly one struct.
Duplicate field names are retained and ambiguous lookups report an evaluation
error. Whole `--data` datagrams bind zero elements as an empty bag, one as-is,
and many as a bag.

```sh
# rows.ion contains two top-level structs, not a list.
printf '{a: 1}\n{a: 2}\n' > rows.ion
partiql query --data t=rows.ion -e 'SELECT VALUE r.a FROM t AS r'
# $bag::[1, 2]

partiql query --data t=rows.ion --each t -e 't.a'
# 1, then 2 as separate top-level results

partiql query --data t=rows.ion --output-format binary -e 't' > result.10n
cat result.10n | partiql query --data t=- -e 't'
```

`--each NAME` evaluates the script once per top-level element of that named
binding, in order. Empty input evaluates no statements. `--output-format binary`
writes one binary datagram. Failed statements exit 1 while retaining earlier
results, including a valid binary datagram for binary output.

`--data-schema NAME=FILE` validates a binding before any statement runs;
`--env-schema FILE` validates the environment. `--schema-type TYPE` selects a
schema type, defaulting to `document`. Validation is per element unless
`--schema-document` selects whole-datagram validation. Schemas describe raw Ion
and its PartiQL annotations. Every violation is reported with its path.

```sh
printf '$ion_schema_2_0 schema_header::{} type::{name: row, type: struct} schema_footer::{}' > rows.isl
partiql query --data t=rows.ion --data-schema t=rows.isl --schema-type row -e 't'
```

## JSON input and output

`--input-format json` selects strict JSON for every `--data` and `--env`
file, including stdin. Each file must hold exactly one document. `--data`
binds it as-is; `--env` requires an object. Empty input and JSON Lines are
rejected. `--each NAME` iterates a top-level JSON array in order, runs once
for another document, and runs nothing for an empty array.

`--output-format json` writes one JSON document per evaluation result,
followed by a newline. Multiple statements or `--each` produce multiple
documents. `--compact` makes this JSON Lines; the default uses indentation.
The input reader still accepts only one document, so a stream of results
must be split before it can be read back. Earlier complete results remain
on an evaluation or output error; no partial failing document is written.

```sh
printf '[{"a":1},{"a":2}]' > rows.json
partiql query --input-format json --data t=rows.json --output-format json \
  -e 'CAST((SELECT VALUE r.a FROM t AS r) AS LIST)'
cat rows.json | partiql query --input-format json --data t=- \
  --each t --output-format json --compact -e 't.a'
```

JSON objects map to tuples and arrays to lists. Integers retain all digits;
fractions and exponents become exact decimals with scale. Duplicate object
keys survive. Finite floats write binary64 round-trip spellings but read
back as Int/Decimal. JSON output rejects non-finite floats, `Missing`, bags,
maps, graphs, all temporal and interval values, blobs, clobs and boxed Ion.
For a SELECT bag, explicitly `CAST(... AS LIST)` or use `ORDER BY` to produce
a list. See the [complete value mapping and limits](../partiql-value/README.mbt.md#json-documents).

Input and output formats are independent. `--input-format ion` is the
default and detects text or binary Ion; `--output-format ion` remains the
default output. Ion Schema options cannot be combined with JSON input.

## Embed the CLI

Import `moonrockz/partiql/cli` as `@cli`. `run` accepts arguments without the
program name and returns `Outcome`: text stdout, optional binary stdout, text
stderr and a status. It never writes to process streams. With binary output,
`stdout_bytes` is `Some(bytes)` and `stdout` is empty. The application writes
the selected output and exits with the returned status.

```mbt nocheck
import {
  "moonrockz/partiql/cli",
}
```

The checked examples use `moonrockz/expect` for assertions. Add it with
`moon add moonrockz/expect` and put this import in `moon.pkg` when copying
the test blocks:

```mbt nocheck
import { "moonrockz/expect" } for "test"
```

```mbt check
test "embedded CLI query" {
  let result = @cli.run(["query", "--compact", "-e", "1 + 2"])
  @expect.expect((result.status, result.stdout, result.stderr)).to_equal((0, "3\n", ""))
}
```

The default `Io::unavailable()` rejects file and stdin access. Supply an `Io`
record for file reads/writes, stdin, optional binary readers, color defaults
and the clock used by CURRENT_DATE and related functions. Text readers provide
UTF-8 when byte readers are absent. Help, version and literal `-e` queries
without clock functions work with the default I/O.

```mbt check
test "embedded CLI usage error" {
  let result = @cli.run(["format", "--width", "invalid", "-e", "select 1"])
  @expect.expect(result.status).to_equal(2)
}
```

Build the executable locally with `mise run build:cli`. The executable supports
native and wasm; the CLI library's checked examples run on all four library
targets through `mise run test:docs`.

## YAML input

`--input-format yaml` selects YAML 1.2 Core input for every `--data` and `--env`,
including stdin. There is no extension sniffing. `--env` requires exactly one
mapping document; `--data` binds zero documents as an empty Bag, one as-is, and
many as a Bag. `--each NAME` expands one top-level List; a stream of Lists stays
a sequence of whole Lists. Empty streams and a sole empty List run no evaluations
with `--each`; an explicit empty document runs once with Null. Every binding
loads completely before any statement evaluates, so a malformed later document
produces no query output.

```sh
printf '%s\n' '--- {name: first}' '--- {name: second}' > manifest.yaml
partiql query --input-format yaml --data t=manifest.yaml \
  -e 'SELECT VALUE r.name FROM t AS r'
cat manifest.yaml | partiql query --input-format yaml --data t=- --each t \
  --output-format json --compact -e 't.name'
printf '%s\n' 'n: 4' | partiql query --input-format yaml --env - -e 'n + 1'
```

These produce a bag of two names, two JSON strings, and `5`, respectively.
Input is UTF-8 with YAML BOM support. Exact integers and finite Decimals, core
tags, document-local anchors and bounded aliases follow the
[value codec contract](../partiql-value/README.mbt.md#yaml-input). Mapping keys
must be strings and unique after decoding. Special floats are supported as input
but cannot be written as JSON. Plain `<<` does not perform a merge. YAML 1.1,
UTF-16/32, custom tags, comment preservation and YAML output are not supported.

Limits are 256 nested containers, 1,000,000 expanded nodes and 64 MiB of decoded
scalar UTF-8 bytes per stream, including keys and alias copies; parser work is
also bounded. Ion Schema flags with YAML are usage errors, before input is read.
Usage errors exit 2; decoding, evaluation and output errors exit 1. YAML errors
name the file or stdin, document, line and Unicode column when available.
Ion remains the default output, and `--output-format binary|json` remains
available. JSON rejects Bags and special Float values; explicitly cast SELECT
results to List when JSON output is needed.

```mbt check
test "iterate YAML documents including empty streams" {
  @expect.expect_all(soft => {
    for (source, expected) in [
      ("--- {name: first}\n--- {name: second}", "\"first\"\n\"second\"\n"),
      ("", ""),
      ("---", "null\n"),
    ] {
      let io = { ..@cli.Io::unavailable(), read_stdin: () => source }
      let result = @cli.run([
        "query", "--input-format", "yaml", "--data", "t=-", "--each", "t",
        "--output-format", "json", "--compact", "-e", "CASE WHEN t IS NULL THEN NULL ELSE t.name END",
      ], io~)
      soft.expect(result.status).to_equal(0)
      soft.expect(result.stdout).to_equal(expected)
    }
  })
}
```
