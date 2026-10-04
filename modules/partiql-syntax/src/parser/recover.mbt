// Error recovery (spec M3d §4): recovery points catch an error, record it,
// skip to a synchronizing token and return an Error node.

///|
/// At most this many errors (lexer and parser) are recorded.
let max_errors = 100

///|
/// What a recovery point skips to.
priv enum Sync {
  /// `;` or the end of input; stray closers are skipped.
  Statement
  /// A clause word, `;`, or a closer of an enclosing bracket.
  Clause
  /// `,`, a clause word, `;`, or the list's closer.
  Item
}

///|
fn error_span(e : @ast.ParseError) -> @ast.Span {
  match e {
    Syntax(span~, ..) | Unsupported(span~, ..) => span
  }
}

///|
/// Words that start a clause or a set operation.
let sync_words : Array[String] = [
  "FROM", "LET", "WHERE", "GROUP", "HAVING", "ORDER", "LIMIT", "OFFSET", "UNION",
  "INTERSECT", "EXCEPT",
]

///|
fn is_sync_word(t : @lexer.Token) -> Bool {
  t.kind is Word(w) && sync_words.contains(w.to_upper())
}

///|
/// Whether the tokens `k` and `k + 1` ahead are `c` `c`, touching.
fn Parser::pair_at(self : Parser, k : Int, c : Char) -> Bool {
  let a = self.peek_at(k)
  let b = self.peek_at(k + 1)
  a.kind is Punct(x) &&
  x == c &&
  b.kind is Punct(y) &&
  y == c &&
  a.span.end == b.span.start
}

///|
fn is_closer(t : @lexer.Token) -> Bool {
  t.kind is Punct(')' | ']' | '}')
}

///|
/// Whether the current token ends what is being read: `;`, end of input, a
/// clause word or a closing bracket. A missing closer is taken as present
/// only here.
fn Parser::at_boundary(self : Parser) -> Bool {
  let t = self.peek()
  t.kind is (End | Punct(';')) ||
  is_sync_word(t) ||
  is_closer(t) ||
  self.pair_at(0, '>')
}

///|
/// Records `e`, unless an error at the same position is recorded. At the
/// limit the parse stops: `e` is raised and recovery points re-raise it.
fn Parser::record(
  self : Parser,
  e : @ast.ParseError,
) -> Unit raise @ast.ParseError {
  let start = error_span(e).start
  if self.error_starts.contains(start) {
    return
  }
  if self.errors.length() + self.lex_errors >= max_errors {
    self.stopped = true
    raise e
  }
  self.error_starts.add(start)
  self.errors.push(e)
}

///|
/// Skips tokens up to the synchronizing token of `sync` (not consumed).
/// Brackets opened while skipping are skipped whole; `depth` brackets are
/// already open (opened by the failed body).
fn Parser::skip_to(self : Parser, sync : Sync, depth? : Int = 0) -> Unit {
  let mut depth = depth
  while true {
    let t = self.peek()
    match t.kind {
      End => return
      // `;` cannot be inside brackets: strings and literals are single
      // tokens, so it always ends the skip.
      Punct(';') => return
      Punct(',') if depth == 0 && sync is Item => return
      Punct('(' | '[' | '{') => depth += 1
      Punct('<') if self.pair_at(0, '<') => {
        depth += 1
        ignore(self.advance())
      }
      Punct('>') if self.pair_at(0, '>') =>
        if depth > 0 {
          depth -= 1
          ignore(self.advance())
        } else if sync is Statement {
          ignore(self.advance())
        } else {
          return
        }
      Punct(')' | ']' | '}') =>
        if depth > 0 {
          depth -= 1
        } else if !(sync is Statement) {
          return
        }
      Word(_) if depth == 0 && !(sync is Statement) && is_sync_word(t) => return
      _ => ()
    }
    ignore(self.advance())
  }
}

///|
/// The number of brackets opened in the tokens from index `start` up to the
/// cursor and not closed there.
fn Parser::unclosed_since(self : Parser, start : Int) -> Int {
  let mut depth = 0
  let mut i = start
  while i < self.pos {
    let t = self.tokens[i]
    let pair = i + 1 < self.pos &&
      self.tokens[i + 1].kind == t.kind &&
      t.span.end == self.tokens[i + 1].span.start
    match t.kind {
      Punct('(' | '[' | '{') => depth += 1
      Punct(')' | ']' | '}') => depth = if depth > 0 { depth - 1 } else { 0 }
      Punct('<') if pair => {
        depth += 1
        i += 1
      }
      Punct('>') if pair => {
        depth = if depth > 0 { depth - 1 } else { 0 }
        i += 1
      }
      _ => ()
    }
    i += 1
  }
  depth
}

///|
/// The span of the tokens from index `start` to the last consumed one;
/// empty at the token `start` when none was consumed.
fn Parser::covered(self : Parser, start : Int) -> @ast.Span {
  if self.pos > start {
    self.span_from(start)
  } else {
    let at = self.tokens[start].span.start
    { start: at, end: at, }
  }
}

///|
fn is_too_deep(e : @ast.ParseError) -> Bool {
  e is Syntax(message=m, ..) && m == too_deep
}

///|
/// A recovery point: runs `body`. In recovery mode an error is recorded,
/// the tokens up to the synchronizing token of `sync` are skipped, and
/// `on_error` builds the node for the covered span. The depth error and
/// the error limit go to the statement point.
fn[T] Parser::recover(
  self : Parser,
  sync : Sync,
  body : () -> T raise @ast.ParseError,
  on_error : (@ast.Span) -> T,
) -> T raise @ast.ParseError {
  if !self.recovering {
    return body()
  }
  let start = self.pos
  let depth = self.depth
  let continuation = self.continuation
  body() catch {
    e => {
      if self.stopped || (is_too_deep(e) && !(sync is Statement)) {
        raise e
      }
      self.depth = depth
      self.continuation = continuation
      self.record(e)
      self.skip_to(sync, depth=self.unclosed_since(start))
      if sync is Statement &&
        self.pos == start &&
        !(self.peek().kind is (End | Punct(';'))) {
        ignore(self.advance())
      }
      self.expected.clear()
      self.saw_operator = false
      on_error(self.covered(start))
    }
  }
}

///|
/// Runs `body` with recovery off: trial parses and graph patterns.
fn[T] Parser::strictly(
  self : Parser,
  body : () -> T raise @ast.ParseError,
) -> T raise @ast.ParseError {
  let saved = self.recovering
  self.recovering = false
  errdefer {
    self.recovering = saved
  }
  let result = body()
  self.recovering = saved
  result
}

///|
fn error_expr(span : @ast.Span) -> @ast.Expr {
  make(Error, span)
}

///|
/// A clause recovery point.
fn[T] Parser::clause(
  self : Parser,
  body : () -> T raise @ast.ParseError,
  on_error : (@ast.Span) -> T,
) -> T raise @ast.ParseError {
  self.recover(Clause, body, on_error)
}

///|
/// A list-item recovery point for an expression.
fn Parser::item(
  self : Parser,
  body : () -> @ast.Expr raise @ast.ParseError,
) -> @ast.Expr raise @ast.ParseError {
  self.recover(Item, body, error_expr)
}

///|
/// Consumes the list closer `close` (`)`, `]`, `}` or `>>`).
fn Parser::eat_close(self : Parser, close : String) -> Bool {
  match close {
    ">>" => self.eat_op(">>")
    ")" => self.eat_punct(')')
    "]" => self.eat_punct(']')
    _ => self.eat_punct('}')
  }
}

///|
/// After a list item: `close` ends the list (false), `,` continues it
/// (true). Otherwise "expected `,` or `close`" is raised; in recovery mode
/// it is recorded, the parser skips to `,` or the closer, and a missing
/// closer is taken as present.
fn Parser::list_next(
  self : Parser,
  close : String,
) -> Bool raise @ast.ParseError {
  if self.eat_close(close) {
    return false
  }
  if self.eat_punct(',') {
    return true
  }
  let e = self.error("expected `,` or `\{close}`")
  if !self.recovering {
    raise e
  }
  self.record(e)
  self.skip_to(Item)
  if self.eat_punct(',') {
    return true
  }
  ignore(self.eat_close(close))
  false
}
