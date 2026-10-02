///|
let max_depth = 100

///|
/// The message of the depth guard's syntax error.
let too_deep : String = "nesting is too deep"

///|
/// The parser state: a cursor over the tokens, the nesting depth, and what
/// the parser tried at the current position (for error messages).
priv struct Parser {
  tokens : Array[@lexer.Token]
  mut pos : Int
  mut depth : Int
  expected : Array[String]
  /// Token positions where a parenthesized join was tried and failed; the
  /// attempt is never repeated there, so parsing stays linear.
  failed_joins : @hashset.HashSet[Int]
  /// Token positions where a parenthesized join was read, with the join and
  /// the position after it; a second visit reuses them (spec M2b 7.3).
  joins : Map[Int, (@ast.FromItem, Int)]
}

///|
fn Parser::new(tokens : Array[@lexer.Token]) -> Parser {
  {
    tokens,
    pos: 0,
    depth: 0,
    expected: [],
    failed_joins: @hashset.from_array([]),
    joins: {},
  }
}

///|
fn Parser::peek(self : Parser) -> @lexer.Token {
  self.tokens[self.pos]
}

///|
/// The token `k` places ahead (the final `End` token repeats).
fn Parser::peek_at(self : Parser, k : Int) -> @lexer.Token {
  let i = self.pos + k
  if i < self.tokens.length() {
    self.tokens[i]
  } else {
    self.tokens[self.tokens.length() - 1]
  }
}

///|
fn Parser::advance(self : Parser) -> @lexer.Token {
  let t = self.peek()
  if !(t.kind is End) {
    self.pos += 1
  }
  self.expected.clear()
  t
}

///|
fn Parser::note(self : Parser, what : String) -> Unit {
  if !self.expected.contains(what) {
    self.expected.push(what)
  }
}

///|
/// A syntax error at the current token.
fn Parser::error(self : Parser, message : String) -> @ast.ParseError {
  let t = self.peek()
  @ast.ParseError::Syntax(
    message~,
    span=t.span,
    expected=self.expected.copy(),
    found=describe(t),
  )
}

///|
fn Parser::fail(self : Parser, message : String) -> Unit raise @ast.ParseError {
  raise self.error(message)
}

///|
fn word_is(token : @lexer.Token, word : String) -> Bool {
  token.kind is Word(w) && w.equal_ignore_ascii_case(word)
}

///|
fn Parser::at_word(self : Parser, word : String) -> Bool {
  if word_is(self.peek(), word) {
    true
  } else {
    self.note(word)
    false
  }
}

///|
fn Parser::at_word_at(self : Parser, k : Int, word : String) -> Bool {
  word_is(self.peek_at(k), word)
}

///|
fn Parser::eat_word(self : Parser, word : String) -> Bool {
  if self.at_word(word) {
    ignore(self.advance())
    true
  } else {
    false
  }
}

///|
fn Parser::expect_word(
  self : Parser,
  word : String,
) -> Unit raise @ast.ParseError {
  if !self.eat_word(word) {
    self.fail("expected \{word}")
  }
}

///|
fn Parser::at_punct(self : Parser, c : Char) -> Bool {
  if self.peek().kind is Punct(p) && p == c {
    true
  } else {
    self.note("`\{c}`")
    false
  }
}

///|
fn Parser::eat_punct(self : Parser, c : Char) -> Bool {
  if self.at_punct(c) {
    ignore(self.advance())
    true
  } else {
    false
  }
}

///|
fn Parser::expect_punct(self : Parser, c : Char) -> Unit raise @ast.ParseError {
  if !self.eat_punct(c) {
    self.fail("expected `\{c}`")
  }
}

///|
/// Whether the next tokens spell `op` as touching punctuation, for
/// operators such as `<<`, `<=`, `<>`, `!=` and `||`.
fn Parser::at_op(self : Parser, op : String) -> Bool {
  let chars = op.to_array()
  for k, c in chars {
    let t = self.peek_at(k)
    guard t.kind is Punct(p) && p == c else {
      self.note("`\{op}`")
      return false
    }
    if k > 0 && self.peek_at(k - 1).span.end != t.span.start {
      self.note("`\{op}`")
      return false
    }
  }
  true
}

///|
fn Parser::eat_op(self : Parser, op : String) -> Bool {
  if self.at_op(op) {
    for _ in 0..<op.length() {
      ignore(self.advance())
    }
    true
  } else {
    false
  }
}

///|
/// Runs `body` one nesting level deeper; deep input is a syntax error, not a
/// stack overflow.
fn[T] Parser::nested(
  self : Parser,
  body : () -> T raise @ast.ParseError,
) -> T raise @ast.ParseError {
  if self.depth >= max_depth {
    raise self.error(too_deep)
  }
  self.depth += 1
  let result = body()
  self.depth -= 1
  result
}

///|
/// An identifier. Reserved words are not identifiers, except the path words
/// when `allow_path_words` (after `.`).
fn Parser::identifier(
  self : Parser,
  allow_path_words? : Bool = false,
) -> @ast.Identifier raise @ast.ParseError {
  let t = self.peek()
  match t.kind {
    Word(w) if !is_reserved(w) ||
      (allow_path_words && path_words.contains(w.to_upper())) => {
      ignore(self.advance())
      { text: w, delimited: false, span: t.span, }
    }
    QuotedIdent(w) => {
      ignore(self.advance())
      { text: w, delimited: true, span: t.span, }
    }
    _ => {
      self.note("an identifier")
      raise self.error("expected an identifier")
    }
  }
}

///|
/// The span from token index `start` to the last consumed token.
fn Parser::span_from(self : Parser, start : Int) -> @ast.Span {
  let first = self.tokens[start].span
  if self.pos == 0 || self.pos <= start {
    return first
  }
  let last = self.tokens[self.pos - 1].span
  { start: first.start, end: last.end, }
}

///|
/// How an error names the token it found (spec M3c §4.1).
fn describe(t : @lexer.Token) -> String {
  match t.kind {
    Word(w) =>
      if is_reserved(w) {
        "keyword `\{w}`"
      } else {
        "identifier `\{w}`"
      }
    QuotedIdent(w) => "identifier `\"\{w}\"`"
    StringLit(s) => {
      let text = if s.length() > 20 {
        s.view(end_offset=20).to_owned() + "…"
      } else {
        s
      }
      "string `'\{text}'`"
    }
    IntLit(n) | DecimalLit(n) | FloatLit(n) => "number `\{n}`"
    IonLit(_, _) => "Ion literal"
    Punct(c) => "`\{c}`"
    End => "end of input"
  }
}
