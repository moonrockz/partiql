// The S-expression tree and its layout. Building the pretty document is
// iterative, so deep trees (long operator chains) do not overflow the stack.

///|
/// An atom, a bracketed list of items separated by spaces, or a
/// concatenation without separators.
priv enum Sx {
  Atom(String)
  Seq(String, Array[Sx], String)
  Cat(Array[Sx])
}

///|
fn list(head : String, items : Array[Sx]) -> Sx {
  Seq("(", [Atom(head)] + items, ")")
}

///|
priv enum Task {
  Visit(Sx)
  MakeSeq(String, Int, String)
  MakeCat(Int)
}

///|
/// The last `n` docs of `out`, in order, removed from `out`.
fn take(out : Array[@pretty.Doc], n : Int) -> Array[@pretty.Doc] {
  let items = out[out.length() - n:].to_owned()
  for _ in 0..<n {
    ignore(out.pop())
  }
  items
}

///|
/// Lisp layout: the first item stays on the opening line; when the list does
/// not fit, every further item goes on its own line, indented by 2.
fn doc(root : Sx) -> @pretty.Doc {
  let tasks : Array[Task] = [Visit(root)]
  let out : Array[@pretty.Doc] = []
  while tasks.pop() is Some(task) {
    match task {
      Visit(Atom(s)) => out.push(@pretty.text(s))
      Visit(Seq(open, items, close)) => {
        tasks.push(MakeSeq(open, items.length(), close))
        for i = items.length() - 1; i >= 0; i = i - 1 {
          tasks.push(Visit(items[i]))
        }
      }
      Visit(Cat(parts)) => {
        tasks.push(MakeCat(parts.length()))
        for i = parts.length() - 1; i >= 0; i = i - 1 {
          tasks.push(Visit(parts[i]))
        }
      }
      MakeSeq(open, n, close) => {
        let items = take(out, n)
        if items.is_empty() {
          out.push(@pretty.text(open + close))
        } else {
          let rest = items[1:].to_owned().map(d => @pretty.line() + d)
          out.push(
            @pretty.group(
              @pretty.text(open) +
              items[0] +
              @pretty.nest(2, @pretty.concat(rest)) +
              @pretty.text(close),
            ),
          )
        }
      }
      MakeCat(n) => out.push(@pretty.concat(take(out, n)))
    }
  }
  out[0]
}

///|
fn layout(x : Sx, width : Int) -> String {
  @pretty.render(doc(x), width~)
}
