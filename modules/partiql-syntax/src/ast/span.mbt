///|
/// A range of source text: UTF-16 code unit offsets, `end` exclusive.
pub(all) struct Span {
  start : Int
  end : Int
} derive(Debug, Eq)

///|
/// The smallest span that covers both spans.
pub fn Span::merge(self : Span, other : Span) -> Span {
  {
    start: if self.start < other.start {
      self.start
    } else {
      other.start
    },
    end: if self.end > other.end {
      self.end
    } else {
      other.end
    },
  }
}

///|
/// 1-based (line, column) of the start and of the end of the span. Lines end
/// at `\n` (a preceding `\r` belongs to the line); columns count UTF-16 code
/// units.
pub fn Span::line_column(
  self : Span,
  source : String,
) -> ((Int, Int), (Int, Int)) {
  (position(source, self.start), position(source, self.end))
}

///|
fn position(source : String, offset : Int) -> (Int, Int) {
  let mut line = 1
  let mut line_start = 0
  let limit = if offset < source.length() { offset } else { source.length() }
  for i in 0..<limit {
    if source.at(i) == '\n'.to_int().to_uint16() {
      line += 1
      line_start = i + 1
    }
  }
  (line, offset - line_start + 1)
}
