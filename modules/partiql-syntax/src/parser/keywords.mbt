///|
/// The reserved words of the Kotlin grammar (`PartiQLTokens.g4` minus its
/// non-reserved words), upper case, without the datetime field words YEAR ..
/// SECOND, which the corpus uses as variable names. A reserved word is not an
/// identifier.
let reserved_words : @hashset.HashSet[String] = @hashset.from_array([
  "ABSOLUTE", "ACTION", "ADD", "ALL", "ALLOCATE", "ALTER", "AND", "ARE", "ARRAY",
  "AS", "ASC", "ASSERTION", "AT", "AUTHORIZATION", "BAG", "BEGIN", "BETWEEN", "BIGINT",
  "BIT", "BLOB", "BOOL", "BOOLEAN", "BY", "CAN_CAST", "CAN_LOSSLESS_CAST", "CASCADE",
  "CASCADED", "CASE", "CAST", "CATALOG", "CHAR", "CHARACTER", "CHECK", "CLOB", "CLOSE",
  "COLLATE", "COLLATION", "COLUMN", "COMMENT", "COMMIT", "CONFLICT", "CONNECT", "CONNECTION",
  "CONSTRAINT", "CONSTRAINTS", "CONTINUE", "CORRESPONDING", "CREATE", "CROSS", "CURRENT",
  "CURRENT_DATE", "CURRENT_TIME", "CURRENT_TIMESTAMP", "CURRENT_USER", "CURSOR",
  "DATE", "DATE_ADD", "DATE_DIFF", "DEALLOCATE", "DEC", "DECIMAL", "DECLARE", "DEFAULT",
  "DEFERRABLE", "DEFERRED", "DELETE", "DESC", "DESCRIBE", "DESCRIPTOR", "DIAGNOSTICS",
  "DISCONNECT", "DISTINCT", "DO", "DOMAIN", "DOUBLE", "DROP", "ELSE", "END", "ESCAPE",
  "EXCEPT", "EXCEPTION", "EXCLUDE", "EXEC", "EXECUTE", "EXPLAIN", "EXTERNAL", "FALSE",
  "FETCH", "FIRST", "FLOAT", "FOR", "FOREIGN", "FOUND", "FROM", "FULL", "GET", "GLOBAL",
  "GO", "GOTO", "GRANT", "GROUP", "HAVING", "IDENTITY", "IMMEDIATE", "IN", "INDEX",
  "INDICATOR", "INITIALLY", "INNER", "INPUT", "INSERT", "INT", "INTEGER", "INTERSECT",
  "INTERVAL", "INTO", "IS", "ISOLATION", "JOIN", "KEY", "LAG", "LANGUAGE", "LAST",
  "LATERAL", "LEAD", "LEFT", "LET", "LEVEL", "LIKE", "LIMIT", "LIST", "LOCAL", "MAP",
  "MATCH", "MISSING", "MODIFIED", "MODULE", "NAMES", "NATIONAL", "NATURAL", "NCHAR",
  "NEW", "NEXT", "NO", "NOT", "NOTHING", "NULL", "NULLS", "NUMERIC", "OF", "OFFSET",
  "OLD", "ON", "ONLY", "OPEN", "OPTION", "OPTIONAL", "OR", "ORDER", "OUTER", "OUTPUT",
  "OVER", "OVERLAPS", "PAD", "PARTIAL", "PARTITION", "PIVOT", "PLACING", "PRECISION",
  "PREPARE", "PRESERVE", "PRIMARY", "PRIOR", "PRIVILEGES", "PROCEDURE", "PUBLIC",
  "READ", "REAL", "RECURSIVE", "REFERENCES", "RELATIVE", "REMOVE", "RESTRICT", "RETURNING",
  "REVOKE", "RIGHT", "ROLLBACK", "ROW", "ROWS", "ROW_NUMBER", "SCHEMA", "SCROLL",
  "SECTION", "SELECT", "SESSION", "SESSION_USER", "SET", "SEXP", "SHORTEST", "SMALLINT",
  "SPACE", "SQLCODE", "SQLERROR", "SQLSTATE", "STRING", "STRUCT", "SYMBOL", "SYSTEM_USER",
  "TABLE", "TBLPROPERTIES", "TEMPORARY", "THEN", "TIME", "TIMESTAMP", "TINYINT",
  "TO", "TRANSACTION", "TRANSLATION", "TRUE", "TUPLE", "UNION", "UNIQUE", "UNKNOWN",
  "UNPIVOT", "UPDATE", "UPSERT", "USAGE", "USER", "USING", "VALUE", "VALUES", "VARCHAR",
  "VARYING", "VIEW", "WHEN", "WHENEVER", "WHERE", "WINDOW", "WITH", "WITHOUT", "WORK",
  "WRITE", "ZONE",
])

///|
/// Reserved words that may name a field after `.` (`x.year`, `r.timestamp`).
let path_words : @hashset.HashSet[String] = @hashset.from_array([
  "YEAR", "MONTH", "DAY", "HOUR", "MINUTE", "SECOND", "TIMESTAMP", "DATE", "TIME",
])

///|
fn is_reserved(word : String) -> Bool {
  reserved_words.contains(word.to_upper())
}
