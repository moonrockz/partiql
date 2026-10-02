///|
let punctuation : String = "()[]{},.;:*/%+-<>=!|~?@&^"

///|
/// A cursor over the UTF-16 code units of the source.
priv struct Scanner {
  source : String
  mut pos : Int
}

///|
fn Scanner::at(self : Scanner, ahead : Int) -> Int {
  let i = self.pos + ahead
  if i < self.source.length() {
    self.source.at(i).to_int()
  } else {
    -1
  }
}

///|
fn Scanner::text(self : Scanner, start : Int, end : Int) -> String {
  self.source.view(start_offset=start, end_offset=end).to_owned()
}

///|
fn is_digit(c : Int) -> Bool {
  c >= '0'.to_int() && c <= '9'.to_int()
}

///|
fn is_word_start(c : Int) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  c == '_'.to_int() ||
  c == '$'.to_int()
}

///|
fn is_word_char(c : Int) -> Bool {
  is_word_start(c) || is_digit(c)
}

///|
fn is_space(c : Int) -> Bool {
  c == ' '.to_int() ||
  c == '\t'.to_int() ||
  c == '\n'.to_int() ||
  c == '\r'.to_int() ||
  c == 0x0B ||
  c == 0x0C
}

///|
fn error(message : String, start : Int, end : Int) -> @ast.ParseError {
  @ast.ParseError::Syntax(message~, span={ start, end, }, expected=[], found="")
}

///|
/// Skips whitespace and comments, and records each comment in `comments`.
fn Scanner::skip_trivia(
  self : Scanner,
  comments : Array[@ast.Comment],
) -> Unit raise @ast.ParseError {
  while true {
    let c = self.at(0)
    if is_space(c) {
      self.pos += 1
    } else if c == '-'.to_int() && self.at(1) == '-'.to_int() {
      let start = self.pos
      while self.at(0) != -1 && self.at(0) != '\n'.to_int() {
        self.pos += 1
      }
      let end = if self.pos > start && self.at(-1) == '\r'.to_int() {
        self.pos - 1
      } else {
        self.pos
      }
      comments.push({
        kind: Line,
        text: self.text(start, end),
        span: { start, end, },
      })
    } else if c == '/'.to_int() && self.at(1) == '*'.to_int() {
      let start = self.pos
      self.pos += 2
      while !(self.at(0) == '*'.to_int() && self.at(1) == '/'.to_int()) {
        if self.at(0) == -1 {
          raise error("unterminated comment", start, start + 2)
        }
        self.pos += 1
      }
      self.pos += 2
      comments.push({
        kind: Block,
        text: self.text(start, self.pos),
        span: { start, end: self.pos, },
      })
    } else {
      break
    }
  }
}

///|
/// A quoted run (`'...'` or `"..."`) where a doubled quote is an escape.
fn Scanner::quoted(self : Scanner, quote : Int) -> String raise @ast.ParseError {
  let start = self.pos
  self.pos += 1
  let buf = StringBuilder()
  let mut chunk = self.pos
  while true {
    let c = self.at(0)
    if c == -1 {
      raise error(
        if quote == '\''.to_int() {
          "unterminated string"
        } else {
          "unterminated quoted identifier"
        },
        start,
        start + 1,
      )
    }
    if c == quote {
      buf.write_string(self.text(chunk, self.pos))
      if self.at(1) == quote {
        buf.write_char(quote.unsafe_to_char())
        self.pos += 2
        chunk = self.pos
      } else {
        self.pos += 1
        break
      }
    } else {
      self.pos += 1
    }
  }
  buf.to_string()
}

///|
fn Scanner::number(self : Scanner) -> TokenKind {
  let start = self.pos
  while is_digit(self.at(0)) {
    self.pos += 1
  }
  let mut decimal = false
  if self.at(0) == '.'.to_int() {
    decimal = true
    self.pos += 1
    while is_digit(self.at(0)) {
      self.pos += 1
    }
  }
  let c = self.at(0)
  if c == 'e'.to_int() || c == 'E'.to_int() {
    let sign = self.at(1) == '+'.to_int() || self.at(1) == '-'.to_int()
    let first_digit = if sign { 2 } else { 1 }
    if is_digit(self.at(first_digit)) {
      self.pos += first_digit
      while is_digit(self.at(0)) {
        self.pos += 1
      }
      return FloatLit(self.text(start, self.pos))
    }
  }
  let text = self.text(start, self.pos)
  if decimal {
    DecimalLit(text)
  } else {
    IntLit(text)
  }
}

///|
/// Whether a `.` here continues a path (after a name or a closing bracket)
/// rather than starting a number such as `.5`.
fn continues_path(previous : Token?, pos : Int) -> Bool {
  match previous {
    Some({ kind: Word(_) | QuotedIdent(_) | Punct(')' | ']' | '}'), span, }) =>
      span.end == pos
    _ => false
  }
}

///|
/// The tokens of `source` and its comments.
fn scan(
  source : String,
) -> (Array[Token], Array[@ast.Comment]) raise @ast.ParseError {
  let s : Scanner = { source, pos: 0, }
  let tokens : Array[Token] = []
  let comments : Array[@ast.Comment] = []
  while true {
    s.skip_trivia(comments)
    let start = s.pos
    let c = s.at(0)
    let kind : TokenKind = if c == -1 {
      End
    } else if is_word_start(c) {
      while is_word_char(s.at(0)) {
        s.pos += 1
      }
      Word(s.text(start, s.pos))
    } else if is_digit(c) ||
      (
        c == '.'.to_int() &&
        is_digit(s.at(1)) &&
        !continues_path(tokens.last(), start)
      ) {
      s.number()
    } else if c == '\''.to_int() {
      StringLit(s.quoted(c))
    } else if c == '"'.to_int() {
      QuotedIdent(s.quoted(c))
    } else if c == '`'.to_int() {
      ion_literal(s)
    } else if punctuation.contains_code_unit(c.to_uint16()) {
      s.pos += 1
      Punct(c.unsafe_to_char())
    } else {
      raise error(
        "unexpected character `\{c.unsafe_to_char()}`",
        start,
        start + 1,
      )
    }
    tokens.push({ kind, span: { start, end: s.pos, }, })
    if kind is End {
      break
    }
  }
  (tokens, comments)
}

///|
/// Splits PartiQL text into tokens. The last token is `End`.
pub fn lex(source : String) -> Array[Token] raise @ast.ParseError {
  scan(source).0
}

///|
/// The tokens of `source` and its comments, in source order.
pub fn lex_with_comments(
  source : String,
) -> (Array[Token], Array[@ast.Comment]) raise @ast.ParseError {
  scan(source)
}
