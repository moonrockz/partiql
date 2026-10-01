///|
/// The kind of a token. Keywords are `Word`s: the parser decides which words
/// are keywords. Punctuation is one character per token; the parser composes
/// `<<`, `<=`, `||` and similar operators from touching tokens.
pub(all) enum TokenKind {
  /// A regular identifier or keyword, as written.
  Word(String)
  /// `"name"`, with `""` unescaped.
  QuotedIdent(String)
  /// `'text'`, with `''` unescaped.
  StringLit(String)
  /// Digits only.
  IntLit(String)
  /// Digits with a `.`, no exponent.
  DecimalLit(String)
  /// A number with an exponent.
  FloatLit(String)
  /// The text between the backticks of an Ion literal, and its value (the
  /// lexer reads the text once, to check it).
  IonLit(String, @ion_core.IonValue)
  Punct(Char)
  End
} derive(Debug)

///|
/// Structural equality; Ion values compare with `IonValue::equals`.
pub impl Eq for TokenKind with fn equal(a, b) {
  match (a, b) {
    (IonLit(x, xv), IonLit(y, yv)) => x == y && xv.equals(yv)
    (Word(x), Word(y))
    | (QuotedIdent(x), QuotedIdent(y))
    | (StringLit(x), StringLit(y))
    | (IntLit(x), IntLit(y))
    | (DecimalLit(x), DecimalLit(y))
    | (FloatLit(x), FloatLit(y)) => x == y
    (Punct(x), Punct(y)) => x == y
    (End, End) => true
    _ => false
  }
}

///|
pub(all) struct Token {
  kind : TokenKind
  span : @ast.Span
} derive(Debug, Eq)

///|
/// A short description for error messages.
pub fn TokenKind::describe(self : TokenKind) -> String {
  match self {
    Word(w) => "identifier \{w}"
    QuotedIdent(w) => "identifier \"\{w}\""
    StringLit(s) => "string '\{s}'"
    IntLit(n) | DecimalLit(n) | FloatLit(n) => "number \{n}"
    IonLit(_, _) => "Ion literal"
    Punct(c) => "'\{c}'"
    End => "end of input"
  }
}
