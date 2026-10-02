# moonrockz/partiql

The `partiql` command-line tool.

```bash
moonx moonrockz/partiql --help
moonx moonrockz/partiql version
moonx moonrockz/partiql format query.sql           # print canonical PartiQL
moonx moonrockz/partiql format --write *.sql       # rewrite files in place
moonx moonrockz/partiql format -e 'select a from t'
cat query.sql | moonx moonrockz/partiql format     # read stdin
```

`format` keeps comments. A parse error prints `file:line:column: message`
and exits with status 1.

Native binaries for Linux, macOS and Windows are attached to each
[GitHub release](https://github.com/moonrockz/partiql/releases).
