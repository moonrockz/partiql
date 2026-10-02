# Roadmap

The first work is the PartiQL data model and the parser. Each milestone has
its own design spec before implementation starts. The conformance harness
measures the exit criteria (see [conformance.md](conformance.md)).

| Milestone | Content | Exit criteria |
|---|---|---|
| M0 Setup | Workspace, stub modules, conformance harness, CI, release, docs | CI green; the harness reports; docs and tracking exist |
| [M1 Data model](https://github.com/moonrockz/partiql/issues/1) | `Value` ADT, absent values, list/bag/tuple semantics, equality and total ordering, PartiQL-encoded Ion codec | All `env` and `output` values in the corpus round-trip (`codec` check) |
| [M2 Parser](https://github.com/moonrockz/partiql/issues/2) | Lexer, AST, parser, embedded Ion literals | `success/syntax` and `fail/syntax` pass; all evaluation statements parse (`syntax` and `eval-parse` checks) |
| [M3 Printer and errors](https://github.com/moonrockz/partiql/issues/3) | AST printer, errors with source spans | Parse, print and parse again gives an equal AST for every corpus statement |
| Later | Static analysis, logical plan, `partiql-eval`, CLI REPL, tree-sitter corpus | Defined in later specs |

## M0 Setup

Complete. The workspace has the modules `partiql-value`, `partiql-syntax`,
`partiql` and `partiql-conformance`. The harness runs the full partiql-tests
corpus with a ratchet baseline.

## M1 Data model

Status: done, with M1b (MAP and graph): `codec` passes all 6,822 corpus
values. Property laws cover identity, equality,
ordering and the codec.

The `Value` type covers every PartiQL value: the absent values `NULL` and
`MISSING`, the Ion scalars, lists, bags and tuples. Tuples allow duplicate
attribute names, and an attribute value is never `MISSING`. Equality and the
total order follow the specification (the order of `ORDER BY`). The codec reads
and writes the PartiQL-encoded Ion forms that partiql-tests uses, including
the legacy and the new `$date` and `$time` forms.

## M2 Parser

Status: done for queries (DQL). `syntax` passes 425 of 425 applicable cases;
`eval-parse` passes every statement except three corpus defects (see
`conformance.md`).

The lexer handles case-insensitive keywords, quoted identifiers and Ion
literals in backticks. The parser is hand-written recursive descent with a
precedence ladder, and builds a typed syntax tree with spans. Besides the
Kotlin grammar's query language it parses the spec forms `LATERAL`,
`GROUP ALL`, `TABLE` and `CORRESPONDING` that the corpus uses.

M2b adds graph pattern matching (GPML, RFC 0033): `(g MATCH …)` and
`FROM g MATCH …`, with selectors, restrictors, path variables, node, edge and
group patterns in all seven edge directions, quantifiers, label expressions
and `WHERE` filters.

Next: M3, the printer and error messages. DML, DDL and window functions come
with later milestones.

## M3 Printer and errors

M3 has four parts, done in this order:

- **M3a (done): canonical printer.** `print` writes a syntax tree back as
  canonical PartiQL text, and `format` parses a script and prints it,
  keeping its comments. `parse_script` parses several statements separated
  by `;`. The `print-roundtrip` conformance check parses, prints and parses
  every corpus statement again: all 5310 statements that parse give the same
  tree. The CLI has its first working command, `partiql format`.
- **M3c (done): diagnostics.** `render` prints a parse error rustc style:
  the location (line and character column), the source line, a marker, and
  what was expected. Messages name keywords as keywords, expected lists are
  curated (operators fold into "an operator"), lexer errors are named, and
  DML/DDL statements report `Unsupported`. `to_sexp` prints a syntax tree as
  an S-expression (laid out with `moonrockz/pretty`). The CLI gains
  `partiql parse`, `partiql check` and a global `--color`.
- **M3b (done): pretty layout.** `print`, `print_script` and `format`
  take an optional `width`. Without it they print the canonical one-line
  form as before; with it, `moonrockz/pretty` lays the statement out: a
  statement that fits stays on one line, a wider one puts each clause on its
  own line, and long lists, joins, operator chains, calls, CASE, subqueries
  and graph MATCH break further (2-space indentation). The
  `pretty-roundtrip` conformance check prints every corpus statement at
  width 40 and parses it again: all 5310 statements that parse give the same
  tree. `partiql format` prints the layout at width 80, with `--width N`
  and `--compact` (the one-line form).
- **M3d: error recovery.** Several diagnostics per statement.

## Tracking

Tasks are tracked with beads (`bd ready`). The public roadmap is in the GitHub
[milestones](https://github.com/moonrockz/partiql/milestones), with one epic
issue each:

- M1: [#1](https://github.com/moonrockz/partiql/issues/1) (beads `partiql-9er`)
- M2: [#2](https://github.com/moonrockz/partiql/issues/2) (beads `partiql-zhj`)
- M3: [#3](https://github.com/moonrockz/partiql/issues/3) (beads `partiql-sfz`)
