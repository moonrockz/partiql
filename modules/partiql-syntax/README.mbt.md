# moonrockz/partiql-syntax

A PartiQL parser and printer for MoonBit: queries (DQL), including graph
`MATCH` (GPML), into a typed syntax tree with source spans, and back to
canonical text.

```moonbit
let statement = @syntax.parse("SELECT a FROM t WHERE a > 1")
```

`print` writes a tree back as canonical text, and `format` does parse and
print for a whole script, keeping its comments:

```moonbit
let text = @syntax.format("select a from t -- note")
// text == "SELECT a FROM t;\n-- note\n"
```

| Package | Content |
|---|---|
| `moonrockz/partiql-syntax` | `parse(String) -> Statement raise ParseError` |
| `moonrockz/partiql-syntax/ast` | the syntax tree, `Span`, `ParseError` |
| `moonrockz/partiql-syntax/lexer` | `lex(String) -> Array[Token]` |
| `moonrockz/partiql-syntax/parser` | `parse_statement`, `parse_expression`, `parse_script` |
| `moonrockz/partiql-syntax/printer` | `print`, `print_script` |

Errors: `ParseError::Syntax(message~, span~, expected~, found~)` for invalid
input. `ParseError::Unsupported` is reserved for valid PartiQL that a later
version parses; nothing raises it yet.
`Span::line_column(source)` gives 1-based line and column numbers.

`render` prints a parse error for people, and `to_sexp` prints a tree as an
S-expression:

```moonbit
let source = "SELECT FROM t"
let text = try {
  ignore(@syntax.parse(source))
  ""
} catch {
  e => @syntax.render(e, source, name="query.sql")
}
// error: expected an expression, found keyword `FROM`
//  --> query.sql:1:8
```

Input nested more than 100 levels deep (parentheses, subqueries, collections,
graph groups) is a `Syntax` error, "nesting is too deep", on every target.

See `docs/architecture.md` and `docs/conformance.md` in the repository.
