// The moonrockz/partiql-syntax module: the PartiQL lexer, AST and parser.

name = "moonrockz/partiql-syntax"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/moonrockz/partiql"

license = "Apache-2.0"

keywords = [ "partiql", "sql", "query", "parser", "ast" ]

description = "A PartiQL parser for MoonBit."

source = "src"

// Derived Eq/Debug methods on public types (krueger pattern).

warnings = "-implicit_impl_as_method"

import {
  "moonrockz/ion@0.2.0",
  "moonrockz/pretty@0.1.0",
  "moonrockz/expect@0.6.0",
}
