# 4 · Views

You're writing the loader for the arena game's scripts. It reads a script file into a `String` and splits it into lines for the parser. Copying every line would cost memory and time, so each line should be a view: an address and a length inside the loaded text. In C++ you'd reach for a `std::string_view`, and this is the bug it invites:

```cpp
std::string source = readText("arena.script");
std::vector<std::string_view> lines;
splitLines(source, lines);        // each view points into source's buffer
source += "\n";                   // may move the buffer: every view in 'lines' now dangles
parse(lines);                     // reads freed memory
```

In Rayo you write the same code, with no annotations, and the compiler catches the bug:

```swift
func readText(_ path: StringView) throws(IoError) -> String { ... }
func splitLines(_ text: StringView, into out: mutable List<StringView>) { ... }
func parse(_ lines: Span<StringView>) { ... }

func loadScript(_ path: StringView) throws(IoError) {
    var source = try readText(path)
    var lines = List<StringView>()
    splitLines(source.view, into: &lines)     // 'lines' now borrows 'source'
    source.append("\n")                       // error: 'source' is borrowed by 'lines' (used below)
    parse(lines.span)
}
```

Change `source` only after the last use of `lines`, and the code compiles:

```swift
    splitLines(source.view, into: &lines)
    parse(lines.span)                         // the last use of 'lines'
    source.append("\n")                       // fine: nothing borrows 'source' any more
```

The compiler never looked inside `splitLines`. Its signature alone tells the caller that `lines` may now hold views of `source`, and the compiler checks the body of `splitLines` against that same signature.

## Views

**A view is a value that borrows memory something else owns** ([02](../spec/02-views-and-dependencies/scoped-values.md#scoped-values)). Taking one copies nothing.

**You'll use three views all the time, and each holds an address and a count:**

- `Span<T>`, which reads a run of elements;
- `MutableSpan<T>`, which can also change them;
- `StringView`, which reads UTF-8 text.

```swift
let all: Span<Enemy> = enemies.span       // the list's elements, read-only
let firstTwo = enemies[0..<2]             // a range of them: also a Span<Enemy>
var hot = &enemies.span                   // a MutableSpan<Enemy>: '&' asks for the mutable form
let text: StringView = source.view        // the string's bytes
let word = text[0..<5]                    // a range of bytes: also a StringView
let name: StringView = "grunt"            // the literal's bytes, which last for the whole run
```

**A string is indexed by byte offset.** A range of a string or string view must start and end on Unicode scalar boundaries, or taking it panics. So a string view always holds whole UTF-8 sequences ([04](../spec/04-types/collections.md#strings)).

**`Span` and `StringView` are copyable**: a copy is a second view of the same memory.

**A `MutableSpan` is move-only**, since two copies would be two ways to change the same elements at once.

## When a view is scoped

```swift
struct Token(var text: StringView, var line: Int): Scoped   // a token views the script's text
struct Label(var text: StringView)                          // error: a struct with a scoped field must be declared 'Scoped'
```

**A view of memory that can be freed must stay within the scope that lent it** ([02](../spec/02-views-and-dependencies/scoped-values.md#scoped-values)). Inside that scope, the compiler sees every borrow, so it can reject freeing the memory while the view lives.

**A type whose values must stay in their scope conforms to the marker protocol `Scoped`.** Its values are **scoped values**.

**A scoped value can live in locals and parameters, and inside other scoped values.** It can't go anywhere it could outlive what it borrows ([02](../spec/02-views-and-dependencies/scoped-values.md#where-a-scoped-value-can-go)), such as:

- a global;
- a field of a type that isn't scoped;
- a local that lives across an `await`, which chapter 7 teaches ([Concurrency](07-concurrency.md)).

**A type that holds a scoped value is scoped too.** A struct with a field of a scoped type says so with `: Scoped` ([02](../spec/02-views-and-dependencies/scoped-values.md#which-types-are-scoped)).

**A generic type is scoped when what it holds is.** `List<StringView>` and `List<Token>` own their buffers, but the views inside them borrow, so each list must stay within the scope too.

**A scoped type says only that its values must stay in their scope, not what they borrow.** The compiler works that out for each value.

## What a view carries

**Each scoped value has a dependency set: the places it borrows, each shared or exclusive** ([02](../spec/02-views-and-dependencies.md#dependencies)). What a value **carries** is its dependency set.

```swift
let text = source.view                    // carries 'source', shared
let word = text[0..<5]                    // carries what 'text' carries
let tok = Token(text: word, line: 1)      // so does the token that holds it
source.append("!")                        // error: 'source' is borrowed by 'tok' (used below)
log(tok.text)

var hot = &enemies.span                   // carries 'enemies', exclusive
let n = enemies.count                     // error: 'enemies' is borrowed by 'hot' (used below)
hot[0].hp = 0
```

**Until the value's last use, every place in its set counts as borrowed**, with its kind, and the law of exclusivity applies to it ([Borrowing](03-borrowing.md)).

**A view taken from a place borrows that place**, since the view reaches only that place's storage and what the place owns.

**A value made from a view carries everything the view carries**: a copy of the view, a range of it, and a struct or list that holds it.

**A value with a `deinit` of its own keeps its set borrowed until it's destroyed**, since the `deinit` may read what the value borrows. A `List` is an exception: its `deinit` only destroys its elements and frees its buffer, so a `List<StringView>`'s borrows end at its last use ([02](../spec/02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)).

## What a call's result borrows

```swift
func longest(_ lines: Span<StringView>) -> StringView { ... }

let title = longest(lines.span)           // borrows 'lines', and what 'lines' carries: 'source'
source.append("\n")                       // error: 'source' is borrowed by 'title' (used below)
log(title)
```

**A call's result borrows what the call was given** ([02](../spec/02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)). The caller never looks inside the function. From the signature alone, it assumes the result borrows everything the function could reach:

- each argument passed borrowed or `mutable`, `self` included;
- everything those arguments carry;
- what each `owned` argument carries, but not the argument itself, which the function now owns.

**A span, a string view or a number is the exception: it lends only what it carries, never itself, to a result made of spans and string views** ([02](../spec/02-views-and-dependencies/dependency-projection-and-results.md#shallow-values)). That includes a list or struct of them. Such a result can point only where the argument points, never into the argument's own bytes. This holds whether the argument is a variable or a temporary. So `grid.row(y + 1)` borrows `grid` alone.

**A `MutableSpan` gets no such exception**, since it is move-only.

## Storing views through a `mutable` argument

```swift
var lines = List<StringView>()
splitLines(source.view, into: &lines)     // 'lines' takes on what 'source.view' carries: 'source'
var names = List<StringView>()
names.append(banner.view)                 // 'self' absorbs too: 'names' takes on 'banner'

struct Scanner(var text: StringView, var pos: Int = 0): Scoped {
    mutating func scan(into out: mutable List<Token>) { ... }
}

var scanner = Scanner(text: source.view)
scanner.scan(into: &tokens)               // 'tokens' takes on what 'scanner' carries: 'source'
scanner.pos = 0                           // fine: 'tokens' doesn't borrow 'scanner' itself
use(tokens)
```

**After a call, each scoped `mutable` argument takes on what the other arguments borrow.** This is **absorption** ([02](../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)), and it's how `lines` learns that it borrows `source`.

**The caller assumes the function stores whatever it could.** The signature of `splitLines` can't say whether it stores views of `text` into `out`, so the caller assumes it does.

**A `mutating` method's `self` absorbs too.**

**Only a scoped argument absorbs.** A `List<Int>` holds no views, so it takes on nothing.

**A span, a string view or a number lends an absorbing argument only what it carries, as it does a result.** So `lines` borrows `source`, not the view.

**Another `mutable` argument lends what it carries, not itself.** So `tokens` borrows the text the scanner views, and the scanner can move on while `tokens` is in use.

### What the function may keep

```swift
func defaultName() -> StringView {
    let s: String = "grunt"
    return s.view                         // error: the result borrows local 's', which is destroyed on return
}

func addDefault(into out: mutable List<StringView>) {
    let s: String = "grunt"
    out.append(s.view)                    // error: 'out' would borrow local 's', which is destroyed on return
    out.append("grunt")                   // fine: a view of a literal borrows nothing
}
```

**A function can return or store only what its caller lent it** ([02](../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)). The caller trusts the signature, and the compiler holds the body to it.

**A function's locals are its own, so no view of one may leave it.** They're destroyed when the function returns.

**So neither side needs an annotation.** Inside `splitLines`, every line stored into `out` is a range of `text`, which the caller lent.

## A result that borrows one argument: `where`

**A `where` clause narrows what a result borrows** ([02](../spec/02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in)).

**By default a result borrows what every argument lends, even one the function only reads.** That gets in a parser's way when it looks a token up in a symbol table, then moves its lexer on. Here the lexer owns the script's text, so a token's text borrows the lexer itself:

```swift
struct Lexer(var text: String, var pos: Int = 0)

extension SymbolTable {
    func find(_ key: StringView) -> Span<Symbol>? { ... }
}

let tok = lexer.peek()                    // a Token whose text borrows 'lexer'
let syms = symbols.find(tok.text)         // borrows 'symbols', and what the key carries: 'lexer'
lexer.advance()                           // error: 'lexer' is borrowed by 'syms' (used below)
use(syms)
```

**The key is only compared, never kept.** Say so, and the result borrows the table alone:

```swift
extension SymbolTable {
    func find(_ key: StringView) -> Span<Symbol>?
        where return borrows self { ... }   // the result borrows only the table
}

let tok = lexer.peek()
let syms = symbols.find(tok.text)         // borrows 'symbols' only
lexer.advance()                           // fine: 'tok' was last used above
use(syms)
```

**Each item of the clause names a subject and what it borrows.** The subject is `return` or a `mutable` parameter:

- `return borrows x`: the parameter `x` and what it carries, and no other parameter;
- `return borrows static`: only global `let`s and `const`s, so no argument stays borrowed;
- `out borrows text`: the `mutable` parameter `out` takes on `text`, and not the other arguments.

**The compiler checks the clause against the body**, so a wrong clause is a compile error, never a dangling view:

```swift
func pick(_ a: StringView, _ b: StringView) -> StringView
    where return borrows a {
    copy b                                // error: by its 'where' clause, the result may borrow only 'a'
}
```

## Temporaries

```swift
let text = try readText("arena.script").view    // error: the String dies with this statement, and 'text' is used below
log(text)
```

**A view of a temporary can't outlive its statement** ([02](../spec/02-views-and-dependencies/dependency-projection-and-results.md#temporaries)). A **temporary** is a value that no binding holds, such as a call's result. It's destroyed at the end of the statement that made it.

**Name the value, and it lives to the end of its scope:**

```swift
let source = try readText("arena.script")       // the binding owns the String
let text = source.view                           // fine
log(text)
```

**The condition of an `if`, `guard` or `while` counts as a statement of its own**, so its temporaries are gone before the body runs.

**A `for` loop keeps the temporaries of its sequence until the loop ends.**

**A temporary span or string view doesn't tie its result to the statement.** In `splitLines(source.view, into: &lines)`, `source.view` is a temporary, yet `lines` outlives it. A string view lends only what it carries, `source` ([above](#what-a-calls-result-borrows)). So `source.view[0..<5]` borrows `source` too, not the temporary view.

## Staying valid after a parameter changes: `outlives`

```swift
func copyAll(from src: List<StringView>, into dst: mutable List<StringView>)
    where dst outlives src { ... }

copyAll(from: words, into: &kept)         // 'kept' borrows what 'words' carries: 'source'
words.append("eof")                       // fine: without the clause, 'kept' would borrow 'words' itself
use(kept)
```

**`outlives` says that a subject borrows what a parameter carries, but not the parameter itself** ([02](../spec/02-views-and-dependencies/dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)). So the subject stays valid after that parameter changes or is gone.

**The compiler accepts `outlives x` only when nothing `x` carries can be changed through `x` or end with it.** A `Span` or a `List<StringView>` qualifies. A `MutableSpan` doesn't, since it could change the elements under the views it handed out.

**A result moved out of `x` may also be declared `outlives x`, whatever `x` carries.** `popLast()` is one: the element it moves out of a list carries only what the list carried.

**A `for` loop can collect views of a collection's elements.** The loop gets each element from an **iterator**, a value that walks the collection, by calling its `next()`. A collection's iterator declares `next()` `where return outlives self`, so each element borrows the collection, not the iterator:

```swift
var names = List<StringView>()
for entry in table.entries { names.append(entry.name.view) }   // 'names' borrows 'table'
use(names)                                                     // fine: the loop's iterator is gone
```

## When a view must live longer

**A span or string view can't be kept past the scope that lent it, so long-lived state keeps something else.** Pick by what the data is:

- **A handle.** An element of a pool is named by a `Handle<T>`: a small copyable index, checked at each use, which reads `nil` once the element is removed ([Handles and objects](05-handles-and-objects.md)).
- **A `Slice<T>`.** A range of a buffer held by a `Shared` is named by a `Slice<T>`: a checked view that can be stored anywhere, and reads `nil` once the buffer is gone ([Memory and allocators](06-memory-and-allocators.md)).
- **An owning copy.** Small data can be copied. `String("\(word)")` builds a `String` that owns its text, so it isn't scoped and can go anywhere.

**Each of these costs something, and the code shows it.** A handle or a slice costs a check at each use, and a copy allocates once.

## In the spec

- [02 Scoped values](../spec/02-views-and-dependencies/scoped-values.md#scoped-values): the scoped types, where a scoped value can go, and `~Scoped` in generic code.
- [02 Dependencies](../spec/02-views-and-dependencies.md#dependencies): the six rules. Rules 1 and 2 fill a view's set, rule 3 gives a call's result its set, rule 4 is absorption, rule 5 is what a function may return or store, and rule 6 covers accesses to objects and slices.
- [02 Shallow values](../spec/02-views-and-dependencies/dependency-projection-and-results.md#shallow-values): which arguments lend only what they carry, and to which results.
- [02 Temporaries](../spec/02-views-and-dependencies/dependency-projection-and-results.md#temporaries): full statements, and the temporaries that loops keep.
- [02 When destroying a value counts as using it](../spec/02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it): which values keep what they borrow until they are destroyed.
- [02 Precise dependencies](../spec/02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in): every form of `where` item, and naming a field of a parameter or a result.
- [02 `outlives`](../spec/02-views-and-dependencies/dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives): when the compiler accepts it, and values moved out of an owner.
- [04 Collections and strings](../spec/04-types/collections.md#collections-and-strings): the views beside the owning collections, and how strings are indexed.
- [06 Long-lived views](../spec/06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers): `Slice<T>` and the buffers it views.
