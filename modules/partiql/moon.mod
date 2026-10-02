// The moonrockz/partiql module: the `partiql` command-line tool.
// Run it with `moonx moonrockz/partiql`.

name = "moonrockz/partiql"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/moonrockz/partiql"

license = "Apache-2.0"

keywords = [ "partiql", "sql", "query", "cli" ]

description = "The partiql command-line tool."

source = "src"

// Derived Eq/Debug methods on public types (krueger pattern).

warnings = "-implicit_impl_as_method"

import {
  "moonrockz/partiql-syntax@0.1.0",
  "moonbitlang/x@0.5.5",
  "moonrockz/expect@0.6.0",
}
