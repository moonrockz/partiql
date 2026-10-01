# moonrockz/partiql-syntax

A PartiQL parser for MoonBit: queries (DQL), including graph `MATCH`
(GPML), into a typed syntax tree with source spans.

```moonbit
let statement = @syntax.parse("SELECT a FROM t WHERE a > 1")
```

| Package | Content |
|---|---|
| `moonrockz/partiql-syntax` | `parse(String) -> Statement raise ParseError` |
| `moonrockz/partiql-syntax/ast` | the syntax tree, `Span`, `ParseError` |
| `moonrockz/partiql-syntax/lexer` | `lex(String) -> Array[Token]` |
| `moonrockz/partiql-syntax/parser` | `parse_statement`, `parse_expression` |

Errors: `ParseError::Syntax(message~, span~, expected~, found~)` for invalid
input; `ParseError::Unsupported` for valid PartiQL that this version does not
parse (DML, DDL and window functions).
`Span::line_column(source)` gives 1-based line and column numbers.

See `docs/architecture.md` and `docs/conformance.md` in the repository.
