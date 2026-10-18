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
from Ion files:

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
