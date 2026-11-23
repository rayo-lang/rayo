# 4 · Views

So far, the game has kept numbers in a hit list, and functions have borrowed that list while they use it. The game also loads scripts that tell its enemies what to do. A loader reads a script into a `String` and splits it into lines for the parser. Copying every line would cost memory and time, so each line should refer to the loaded text. In C++ you'd reach for a `std::string_view`, and this is the bug it invites:

```cpp
std::string source = readText("arena.script");
std::vector<std::string_view> lines;
splitLines(source, lines);        // each view points into source's buffer
source += "\n";                   // may move the buffer: every view in 'lines' now dangles
parse(lines);                     // reads freed memory
```

In Rayo you write the same code, with no annotations, and the compiler catches the bug. Reading a file can fail, so `readText` returns a `String!IoError`: the `String` it read, or the `IoError` that stopped it. The value comes first and the error after the `!`, which here has nothing to do with Swift's implicitly unwrapped optionals. `try` takes the `String` out, or returns the error to the caller ([10](../spec/10-errors-and-safety/typed-errors.md#results)):

```rayo
func readText(_ path: &Text) -> String!IoError { ... }
func splitLines(_ text: &Text, into out: mutable &List<&Text>) { ... }
func parse(_ lines: &[&Text]) { ... }

func loadScript(_ path: &Text) -> Void!IoError {
    var source = try readText(path)
    var lines = alloc List<&Text>()
    splitLines(source, into: mutable lines)       // 'lines' now borrows 'source'
    source.append("\n")                           // error: 'source' is borrowed by 'lines' (used below)
    parse(lines)
}
```

Change `source` only after the last use of `lines`, and the code compiles:

```rayo
    splitLines(source, into: mutable lines)
    parse(lines)                                  // the last use of 'lines'
    source.append("\n")                           // fine: nothing borrows 'source' any more
```

The compiler never looked inside `splitLines`. Its signature alone tells the caller that `lines` may now hold references to `source`, and the compiler checks the body of `splitLines` against that same signature.

## Views

**A view is a value that borrows memory something else owns** ([02](../spec/02-views-and-dependencies/scoped-values.md#scoped-values)). The references of chapter 3 are views: a `&Enemy` borrows an enemy, and copies nothing. A list's elements are different from one enemy, since how many there are is known only when the program runs, so a reference to them needs a count as well as an address.

**Some storage has no size of its own, so you only ever reach it through a reference** ([01](../spec/01-values-and-ownership/references.md#unsized-types)). You'll meet two kinds all the time:

- `[T]`, a run of elements, such as the hits in a list;
- `Text`, a run of UTF-8 text, such as the characters in a string.

**A reference to either holds an address and a count.** A `&[T]` reads the elements and a `mutable &[T]` can also change them, and a `&Text` reads the text. A `&` type written on a `let` says that it borrows, as a parameter's type does, so the `let` borrows the place it is given with no mark written, while a `let` with no type writes `&`:

```rayo
let all: &[Int] = hits                   // the hit list's elements, read-only
let firstTwo = &hits[0..<2]              // a range of them: also a &[Int]
var editable = mutable hits.span         // a mutable &[Int], which can change them
let text: &Text = source                 // the string's bytes
let word = &text[0..<5]                  // a range of bytes: also a &Text
let name = "grunt"                       // a literal is a static &Text: its bytes last for the whole run
```

**A `[Int]` can't sit in a variable on its own.** Its count isn't part of its type, so the compiler can't know how much room it takes. You always hold one through a reference:

```rayo
let run: [Int] = hits.span               // error: '[Int]' is unsized; declare 'run' a '&[Int]'
```

**A `&String` turns into a `&Text`, and a `&List<T>` into a `&[T]`, where the type asks for one.** Where a function expects a `&Text`, you give it the `String` itself, which the call lends, and the reference the function gets refers to the string's text ([05](../spec/05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)). A list turns into a reference to its elements the same way. Nothing is copied, so a function that only reads text takes a `&Text`, and its callers lend whatever they have, as `loadScript` does above.

**A string is indexed by byte offset.** A range of a string must start and end on Unicode scalar boundaries, or taking it panics. So a `&Text` always refers to whole UTF-8 sequences ([04](../spec/04-types/collections.md#strings)).

**A `&[T]` or a `&Text` is implicitly copyable.** Every shared reference is, as chapter 3's `&Enemy` is. A copy is a second reference to the same memory, only an address and a count, so it needs no `copy` written ([Moves and copies](02-moves-and-copies.md#adding-to-a-list)).

**A `mutable &[T]` is move-only**, since two copies would be two ways to change the same elements at once.

**`hits.span` is the list's elements, and the mark you write before it says which reference you get.** `&hits.span` reads them, and `mutable hits.span` can change them. A range such as `hits[0..<4]` works the same way, so one name serves both ([04](../spec/04-types/collections.md#shared-and-mutable-views-of-one-collection)).

**Writing through a `mutable &[T]` takes a binding that may change.** `editable[0] = 0` changes an element of `hits` through the reference, so `editable` is a `var`. A `let` that holds a mutable reference can read through it, but never write through it ([01](../spec/01-values-and-ownership/references.md#forwarding-through-a-reference)).

**A function that changes a run of elements takes a `mutable &[T]`.** Inside, the parameter names the elements, so the function lends them on with `mutable`, just as it would lend a variable of its own. At the call, `mutable editable` lends a new reference to the same elements, and `editable` works again once the call returns ([01](../spec/01-values-and-ownership/references.md#reborrowing)):

```rayo
func clear(_ s: mutable &[Int]) { for x in mutable s { x = 0 } }

clear(mutable editable)                  // a new reference to the hits, for this call
editable[0] = 1                          // fine: 'editable' is free again
```

## When a view is scoped

```rayo
struct Token(var text: &Text, var line: Int): Scoped   // a token refers to the script's text
struct Label(var text: &Text)                          // error: a struct with a scoped field must be declared 'Scoped'
struct Banner(var text: static &Text)                  // fine: a static reference, such as a literal, isn't scoped
```

**A view of memory that can be freed must stay within the scope that lent it** ([02](../spec/02-views-and-dependencies/scoped-values.md#scoped-values)). Inside that scope, the compiler sees every borrow, so it can reject freeing the memory while the view lives.

**A type whose values must stay in their scope conforms to the marker protocol `Scoped`.** Its values are **scoped values**, and every reference is one.

**A scoped value can live in locals and parameters, and inside other scoped values.** It can't go anywhere it could outlive what it borrows ([02](../spec/02-views-and-dependencies/scoped-values.md#where-a-scoped-value-can-go)), such as:

- a global;
- a field of a type that isn't scoped;
- a local that lives across an `await`, which chapter 7 teaches ([Concurrency](07-concurrency.md)).

**A type that holds a scoped value is scoped too.** A struct with a field of a scoped type says so with `: Scoped` ([02](../spec/02-views-and-dependencies/scoped-values.md#which-types-are-scoped)).

**A reference to a literal can go anywhere, because nothing ever frees a literal's bytes.** Its type says so: a string literal is a `static &Text`, a **static view** of data that lasts for the whole run, so it isn't scoped. `Banner` above can store one in a plain struct, and a global can hold one too. A `static &Text` turns into a plain `&Text` wherever one is expected. The other way works only for a reference to something that also lasts for the whole run, such as a global `let`: a reference borrowed from a parameter never becomes static, since that memory may be freed.

**`static` works on any type that holds shared references**, such as a `static &[Float]` of elements or a struct of them like `Token` above. A global that holds references is static without `static` written:

```rayo
let keywords: [2 of Token] = [Token(text: "if", line: 0), Token(text: "else", line: 0)]   // static: every reference is to a literal
```

Each `keywords[i]` is a `static Token`, which can go anywhere ([02](../spec/02-views-and-dependencies/scoped-values.md#static-values)).

**A literal under `alloc` is a `String` instead.** `alloc "grunt"` makes a `String` that owns its text, and `alloc "wave \(n)"` formats into a new one, so owned text shows its allocation as a `List` does ([04](../spec/04-types/collections.md#strings)).

**A generic type is scoped when what it holds is.** `List<&Text>` and `List<Token>` own their buffers, but the references inside them borrow, so each list must stay within the scope too.

**A scoped type says only that its values must stay in their scope, not what they borrow.** The compiler works that out for each value.

## What a view carries

**Each scoped value has a dependency set: the places it borrows, each shared or exclusive** ([02](../spec/02-views-and-dependencies.md#dependencies)). What a value **carries** is its dependency set.

```rayo
let text: &Text = source                  // carries 'source', shared
let word = &text[0..<5]                   // carries what 'text' carries
let tok = Token(text: word, line: 1)      // so does the token that holds it
source.append("!")                        // error: 'source' is borrowed by 'tok' (used below)
log("\(tok.text)")

var editable = mutable hits.span          // carries 'hits', exclusive
let n = hits.count                        // error: 'hits' is borrowed by 'editable' (used below)
editable[0] = 0
```

**Until the value's last use, every place in its set counts as borrowed**, with its kind, and the law of exclusivity applies to it ([Borrowing](03-borrowing.md)).

**A reference taken from a place borrows that place**, since the reference reaches only that place's storage and what the place owns.

**A value made from a view carries everything the view carries**: a copy of the reference, a range of what it refers to, and a struct or list that holds it. So `word` carries `source` because it came from `text`, though `source` doesn't appear in its line.

**A value with a `deinit` of its own keeps its set borrowed until it's destroyed**, since the `deinit` may read what the value borrows. A `List` is an exception: its `deinit` only destroys its elements and frees its buffer, so a `List<&Text>`'s borrows end at its last use ([02](../spec/02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)).

## What a call's result borrows

```rayo
func longest(_ lines: &[&Text]) -> &Text { ... }

let title = longest(lines)                // borrows 'lines', and what 'lines' carries: 'source'
source.append("\n")                       // error: 'source' is borrowed by 'title' (used below)
log("\(title)")
```

**A call's result borrows what the call was given** ([02](../spec/02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)). The caller never looks inside the function. From the signature alone, it assumes the result borrows everything the function could reach:

- each argument it borrows, shared or for change, `self` included;
- everything those arguments carry;
- what each argument the function owns carries, but not the argument itself, which the function now owns.

**A shared reference, or a number, is the exception: it lends only what it carries, never itself, to a result made of shared references and numbers** ([02](../spec/02-views-and-dependencies/dependency-projection-and-results.md#shallow-values)). That includes a list or struct of them. Such a result can point only where the argument points, never into the argument's own bytes. This holds whether the argument is a variable or a temporary. So `grid.row(y + 1)` borrows `grid` alone.

**A `mutable &[T]` gets no such exception**, since it is move-only.

## Storing views through a `mutable` argument

```rayo
var lines = alloc List<&Text>()
splitLines(source, into: mutable lines)       // 'lines' takes on what the reference to 'source' carries: 'source'
var names = alloc List<&Text>()
names.append(banner)                          // 'self' absorbs too: 'names' takes on 'banner'

struct Scanner(var text: &Text, var pos: UInt = 0): Scoped {
    mutating func scan(into out: mutable &List<Token>) { ... }
}

var scanner = Scanner(text: source)
scanner.scan(into: mutable tokens)            // 'tokens' takes on what 'scanner' carries: 'source'
scanner.pos = 0                               // fine: 'tokens' doesn't borrow 'scanner' itself
use(tokens)
```

**After a call, each scoped `mutable` argument takes on what the other arguments borrow.** This is **absorption** ([02](../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)), and it's how `lines` learns that it borrows `source`.

**The caller assumes the function stores whatever it could.** The signature of `splitLines` can't say whether it stores references to `text` into `out`, so the caller assumes it does.

**A `mutating` method's `self` absorbs too.**

**Only a scoped argument absorbs.** A `List<Int>` holds no views, so it takes on nothing.

**A shared reference, or a number, lends an absorbing argument only what it carries.** It lends a call's result the same, as `longest` showed above. So `lines` borrows `source`, not the reference the call made to it.

**Another `mutable` argument lends what it carries, not itself.** So `tokens` borrows the text the scanner refers to, and the scanner can move on while `tokens` is in use.

### What the function may keep

```rayo
func defaultName() -> &Text {
    let s = alloc "grunt"
    return s                              // error: the result borrows local 's', which is destroyed on return
}

func addDefault(into out: mutable &List<&Text>) {
    let s = alloc "grunt"
    out.append(s)                         // error: 'out' would borrow local 's', which is destroyed on return
    out.append("grunt")                   // fine: a literal is a static reference, which borrows nothing
}
```

**A function can return or store only what its caller lent it** ([02](../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)). The caller trusts the signature, and the compiler holds the body to it.

**A function's locals are its own, so no reference to one may leave it.** They're destroyed when the function returns.

**So neither side needs an annotation.** Inside `splitLines`, every line stored into `out` is a range of `text`, which the caller lent.

## A result that borrows one argument: `where`

**A `where` clause narrows what a result borrows** ([02](../spec/02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in)).

**By default a result borrows what every argument lends, even one the function only reads.** That gets in a parser's way when it looks a token up in a symbol table, then moves its lexer on. Here the lexer owns the script's text, so a token's text borrows the lexer itself:

```rayo
struct Lexer(var text: String, var pos: UInt = 0)

extension SymbolTable {
    func find(_ key: &Text) -> (&[Symbol])? { ... }
}

let tok = lexer.peek()                    // a Token whose text borrows 'lexer'
let syms = symbols.find(tok.text)         // borrows 'symbols', and what the key carries: 'lexer'
lexer.advance()                           // error: 'lexer' is borrowed by 'syms' (used below)
use(syms)
```

`tok.text` already holds a `&Text`, so the call takes a copy of that reference, rather than lending the field that holds it. The result is a `(&[Symbol])?`, an optional reference, so it reads `nil` when the table has no such key.

**The key is only compared, never kept.** Say so, and the result borrows the table alone:

```rayo
extension SymbolTable {
    func find(_ key: &Text) -> (&[Symbol])?
        where return borrows self { ... }   // the result borrows only the table
}

let tok = lexer.peek()
let syms = symbols.find(tok.text)         // borrows 'symbols' only
lexer.advance()                           // fine: 'tok' was last used above
use(syms)
```

**Each item of the clause names a subject and what it borrows.** The subject is `return` or a `mutable &T` parameter:

- `return borrows x`: the parameter `x` and what it carries, and no other parameter;
- `return borrows static`: only global `let`s and `const`s, so no argument stays borrowed;
- `out borrows text`: the `mutable &T` parameter `out` takes on `text`, and not the other arguments.

**The compiler checks the clause against the body**, so a wrong clause is a compile error, never a dangling reference:

```rayo
func pick(_ a: &Text, _ b: &Text) -> &Text
    where return borrows a {
    b                                     // error: by its 'where' clause, the result may borrow only 'a'
}
```

## Temporaries

```rayo
let text: &Text = try readText("arena.script")      // error: the String dies with this statement; write 'let source = try readText(…)'
log("\(text)")
```

**A view of a temporary can't outlive its statement** ([02](../spec/02-views-and-dependencies/dependency-projection-and-results.md#temporaries)). A **temporary** is a value that no binding holds, such as a call's result. It's destroyed at the end of the statement that made it.

**Name the value, and it lives to the end of its scope:**

```rayo
let source = try readText("arena.script")       // the binding owns the String
let text: &Text = source                         // fine
log("\(text)")
```

**The condition of an `if`, `guard` or `while` counts as a statement of its own**, so its temporaries are gone before the body runs.

**A `for` loop keeps the temporaries of its sequence until the loop ends.**

**A reference made for an argument doesn't tie the call's result to the statement.** In `splitLines(source, into: mutable lines)`, the `&Text` the call makes from `source` lives only for the call, yet `lines` outlives it. A shared reference lends only what it carries, `source` ([above](#what-a-calls-result-borrows)). So a range of it, such as `&text[0..<5]`, borrows `source` too, not the reference it was taken through.

## Staying valid after a parameter changes: `outlives`

```rayo
func copyAll(from src: &List<&Text>, into dst: mutable &List<&Text>)
    where dst outlives src { ... }

copyAll(from: words, into: mutable kept)      // 'kept' borrows what 'words' carries: 'source'
words.append("eof")                           // fine: without the clause, 'kept' would borrow 'words' itself
use(kept)
```

**`outlives` says that a subject borrows what a parameter carries, but not the parameter itself** ([02](../spec/02-views-and-dependencies/dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)). So the subject stays valid after that parameter changes or is gone.

**The compiler accepts `outlives x` only when nothing `x` carries can be changed through `x` or end with it.** A `&[T]` or a `List<&Text>` qualifies. A `mutable &[T]` doesn't, since it could change the elements under the references it handed out.

**A result moved out of `x` may also be declared `outlives x`, whatever `x` carries.** `popLast()` is one: the element it moves out of a list carries only what the list carried.

**A `for` loop can collect references to a collection's elements.** The loop gets each element from an **iterator**, a value that walks the collection, by calling its `next()`. A collection's iterator declares `next()` `where return outlives self`, so each element borrows the collection, not the iterator:

```rayo
var names = alloc List<&Text>()
for entry in &table.entries { names.append(entry.name) }    // 'names' borrows 'table'
use(names)                                                  // fine: the loop's iterator is gone
```

## When a view must live longer

**A reference can't be kept past the scope that lent it, so long-lived state keeps something else.** Pick by what the data is:

- **A handle.** An element of a pool is named by a `Handle<T>`: a small copyable index, checked at each use, which reads `nil` once the element is removed ([Handles and objects](05-handles-and-objects.md)).
- **A `Slice<T>`.** A range of a buffer held by a `Shared` is named by a `Slice<T>`: a checked view that can be stored anywhere, and reads `nil` once the buffer is gone ([Memory and allocators](06-memory-and-allocators.md)).
- **An owning copy.** Small data can be copied. `alloc String(word)` builds a `String` that owns a copy of the text `word` refers to, so it isn't scoped and can go anywhere.

**Each of these costs something, and the code shows it.** A handle or a slice costs a check at each use, and a copy allocates once.

## In the spec

- [01 References](../spec/01-values-and-ownership/references.md#references): what a reference is, how `&` and `mutable` make one, and how it forwards to the value it refers to.
- [01 Unsized types](../spec/01-values-and-ownership/references.md#unsized-types): `[T]` and `Text`, why they sit behind a reference, and which references convert to them.
- [01 Reborrowing](../spec/01-values-and-ownership/references.md#reborrowing): lending a new reference to what a held reference refers to.
- [02 Scoped values](../spec/02-views-and-dependencies/scoped-values.md#scoped-values): the scoped types, where a scoped value can go, and `~Scoped` in generic code.
- [04 Runs of elements](../spec/04-types/collections.md#runs-of-elements): the places that hand out a `[T]`, and its members.
- [04 Shared and mutable views of one collection](../spec/04-types/collections.md#shared-and-mutable-views-of-one-collection): one name for a place with both accessors, and two names for a method with a shared and a mutable form.
- [02 Dependencies](../spec/02-views-and-dependencies.md#dependencies): the six rules. Rules 1 and 2 fill a view's set, rule 3 gives a call's result its set, rule 4 is absorption, rule 5 is what a function may return or store, and rule 6 covers accesses to objects and slices.
- [02 Shallow values](../spec/02-views-and-dependencies/dependency-projection-and-results.md#shallow-values): which arguments lend only what they carry, and to which results.
- [02 Temporaries](../spec/02-views-and-dependencies/dependency-projection-and-results.md#temporaries): full statements, and the temporaries that loops keep.
- [02 When destroying a value counts as using it](../spec/02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it): which values keep what they borrow until they are destroyed.
- [02 Precise dependencies](../spec/02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in): every form of `where` item, and naming a field of a parameter or a result.
- [02 `outlives`](../spec/02-views-and-dependencies/dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives): when the compiler accepts it, and values moved out of an owner.
- [04 Collections and strings](../spec/04-types/collections.md#collections-and-strings): the owning collections beside the runs they hold, the two forms of text, and how strings are indexed.
- [05 Places lent where a reference is expected](../spec/05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected): how a `String` or a list given to a call reaches a `&Text` or a `&[T]`.
- [06 Long-lived views](../spec/06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers): `Slice<T>` and the buffers it views.
- [02 Static values](../spec/02-views-and-dependencies/scoped-values.md#static-values): values that refer only to data lasting the whole run, which types take `static`, and which values convert to one.
