# moonrockz/partiql

The `partiql` command-line tool.

```bash
moonx moonrockz/partiql --help
moonx moonrockz/partiql version
moonx moonrockz/partiql format query.sql           # print canonical PartiQL
moonx moonrockz/partiql format --write *.sql       # rewrite files in place
moonx moonrockz/partiql format -e 'select a from t'
cat query.sql | moonx moonrockz/partiql format     # read stdin
moonx moonrockz/partiql check *.sql                # report parse errors
moonx moonrockz/partiql parse -e 'select a from t' # print the syntax tree
```

`format` keeps comments. A parse error prints a rendered diagnostic (the
location, the source line and a marker) and exits with status 1. Colour:
`--color=auto|always|never` (auto: on when stderr is a terminal and `NO_COLOR`
is unset).

Native binaries for Linux, macOS and Windows are attached to each
[GitHub release](https://github.com/moonrockz/partiql/releases).
