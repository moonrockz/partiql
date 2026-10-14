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
