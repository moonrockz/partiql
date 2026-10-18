# moonrockz/partiql-syntax

A PartiQL parser and printer for MoonBit. Parse queries, expressions and graph
MATCH patterns into typed syntax trees with source spans, then print canonical
or width-limited text. DML and DDL forms raise `ParseError::Unsupported`.

## Installation and imports

```sh
moon add moonrockz/partiql-syntax
```

Add an alias because the module name contains a hyphen:

```mbt nocheck
import {
  "moonrockz/partiql-syntax" @syntax,
}
```

The checked examples use `moonrockz/expect` for assertions. Add it with
`moon add moonrockz/expect` and put this import in `moon.pkg` when copying
the test blocks:

```mbt nocheck
import { "moonrockz/expect" } for "test"
```

The examples use the root package. Import a subpackage when working directly
with expression nodes, lexer tokens, logical document layouts or diagnostics.

| Package | Content |
|---|---|
| `moonrockz/partiql-syntax` | Parse, recovery, print, format and diagnostic facade |
| `moonrockz/partiql-syntax/ast` | Public syntax ADTs, `Span`, `ParseError`, comments and scripts |
| `moonrockz/partiql-syntax/lexer` | `lex`, `lex_recovering`, token ADTs |
| `moonrockz/partiql-syntax/parser` | Statement, expression and script parsers |
| `moonrockz/partiql-syntax/printer` | Canonical and pretty printing |
| `moonrockz/partiql-syntax/diagnostic` | Source positions and rendered messages |
| `moonrockz/partiql-syntax/sexp` | S-expression rendering of syntax trees |

## Parse and print a statement

`parse` requires exactly one statement, allowing an optional final semicolon.
`print` omits the semicolon and comments. Use `parse_script` and `print_script`
for multiple statements and preserved comments.

```mbt check
test "parse and print" {
  let statement = @syntax.parse("select a from t where a > 1")
  @expect.expect(@syntax.print(statement)).to_equal("SELECT a FROM t WHERE a > 1")
}
```

Names retain their spelling and whether they were quoted. Literal nodes retain
numeric source text, datetime precision and parsed Ion backtick payloads.
Tree equality therefore compares syntax, including source spans. To compare
a print round trip, print the reparsed result or normalize spans first.

## Format a script

`format` parses the whole script, retains comments and prints each statement
with a terminating semicolon and newline. Without `width`, it uses compact
canonical layout. With `width`, it chooses line breaks; long indivisible tokens
may exceed that width. Errors raise before any formatted output is returned.

```mbt check
test "format with comments" {
  @expect.expect(@syntax.format("select a from t -- note")).to_equal("SELECT a FROM t;\n-- note\n")
}
```

```mbt check
test "format at a chosen width" {
  @expect.expect(@syntax.format("select a, b from t where x = 1", width=20)).to_equal("SELECT a, b\nFROM t\nWHERE x = 1;\n")
}
```

## Recover from invalid input

Strict parsers stop at the first error. `parse_script_recovering` instead
returns a partial script and every diagnostic in source order. Broken regions
contain `Error` nodes; inspect `errors` before using a recovered tree for
execution or rewriting. On valid input it returns the strict parser's tree.

```mbt check
test "recover a script" {
  let result = @syntax.parse_script_recovering("SELECT a, , b FROM t; SELECT 1")
  @expect.expect((result.errors.length(), result.script.statements.length())).to_equal((1, 2))
}
```

## Report source locations

`Span` uses half-open UTF-16 offsets into the original source. `position`
returns 1-based line and Unicode code-point column numbers. The AST helper
`Span::line_column` returns positions for both endpoints with UTF-16 columns.
Use the original source when rendering a diagnostic. `color=true` enables ANSI
color sequences; the default is plain text.

```mbt check
test "render a diagnostic" {
  let source = "SELECT FROM t"
  let text = try {
    ignore(@syntax.parse(source))
    ""
  } catch {
    error => @syntax.render(error, source, name="query.sql")
  }
  @expect.expect(text.contains("query.sql:1:8")).to_be_true()
}
```

`ParseError::Syntax(message~, span~, expected~, found~)` describes invalid
input. `Unsupported` distinguishes recognized forms that are not implemented.
`render_message` also renders evaluator errors at a supplied span. `to_sexp`
produces a readable S-expression with an optional layout width.

```mbt check
test "Unicode source position" {
  let position = @syntax.position("'😀' + x", 7)
  @expect.expect((position.line, position.column)).to_equal((1, 7))
}
```

Input nested more than 100 levels deep, including parentheses, subqueries,
collections and graph groups, raises `Syntax` with "nesting is too deep" on
every target. The parser accepts forms beyond the evaluator's current support;
parsing successfully does not promise successful evaluation.

All checked examples run through `mise run test:docs`. See the repository's
[architecture](../../docs/architecture.md) and
[conformance report](../../docs/conformance.md).
