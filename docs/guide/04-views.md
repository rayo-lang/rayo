# 4 · Views

You're writing the loader for the arena game's scripts. It reads a script file into a `String` and splits it into lines for the parser. Copying every line would cost memory and time, so each line should be a view: an address and a length inside the loaded text. In C++ that is a `std::string_view`, and this is the bug it invites:

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

The compiler never looked inside `splitLines`. Its signature alone tells the caller that `lines` may now hold views of `source`, and the compiler holds the body of `splitLines` to that same signature. This chapter shows how both sides work.

## Views

**A view is a value that borrows memory something else owns** ([02](../spec/02-views-and-dependencies.md#scoped-values)). Taking one copies nothing. Three views come up all the time, and each holds an address and a count, as a C++ `std::span` or a Rust slice does:

- `Span<T>`, which reads a run of elements;
- `MutableSpan<T>`, which may also change them;
- `StringView`, which reads UTF-8 text.

```swift
let all: Span<Enemy> = enemies.span       // the list's elements, read-only
let firstTwo = enemies[0..<2]             // a range of them: also a Span<Enemy>
var hot = &enemies.span                   // a MutableSpan<Enemy>: '&' asks for the mutable form
let text: StringView = source.view        // the string's bytes
let word = text[0..<5]                    // a range of bytes: also a StringView
let name: StringView = "grunt"            // the literal's bytes, which live for the whole run
```

A string is indexed by byte offset. A range of a string or string view must start and end on Unicode scalar boundaries, or taking it panics, so a string view always holds whole UTF-8 sequences ([04](../spec/04-types.md#strings)).

**`Span` and `StringView` are copyable**: a copy is a second view of the same memory. **A `MutableSpan` is move-only**, since two copies would be two ways to change the same elements at once.

## Views are scoped

**A view of memory that can be freed must stay within the scope that lent it.** Its type conforms to the marker protocol `Scoped`, and its values are **scoped values** ([02](../spec/02-views-and-dependencies.md#scoped-values)). A scoped value can live in locals and parameters, and inside other scoped values. It can't go where it could outlive what it borrows ([02](../spec/02-views-and-dependencies.md#where-a-scoped-value-can-go)). Among those places are:

- a global;
- a field of a type that isn't scoped;
- a local that lives across an `await` ([Concurrency](07-concurrency.md)).

**A type that holds a scoped value is scoped too.** A struct with a field of a scoped type says so with `: Scoped` ([02](../spec/02-views-and-dependencies.md#which-types-are-scoped)):

```swift
struct Token(var text: StringView, var line: Int): Scoped   // a token views the script's text
struct Label(var text: StringView)                          // error: a struct with a scoped field must be declared 'Scoped'
```

So `List<StringView>` and `List<Token>` are scoped. Each owns its buffer, but the views inside it borrow, so the list stays within the scope too.

Unlike a Rust struct that holds a reference, a scoped type names no lifetime parameter. The compiler tracks what each value borrows instead, as the rest of this chapter shows.

## What a view carries

**Each scoped value carries a dependency set: the places it borrows, each shared or exclusive** ([02](../spec/02-views-and-dependencies.md#dependencies)). Until the value's last use, every place in its set counts as borrowed with that kind, and the law of exclusivity applies to it ([Borrowing](03-borrowing.md)). A value whose destruction runs code, such as a scoped struct with a `deinit`, keeps its set borrowed until it is destroyed. A `List<StringView>` doesn't: dropping it uses nothing it borrows ([02](../spec/02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)).

Within a function, two rules fill the set:

- **A view taken from a place borrows that place.** `source.view` borrows `source` shared, and `&enemies.span` borrows `enemies` exclusively.
- **A value made from a view carries everything the view carries.** That holds for a copy, a range of it, and a struct or list that holds it.

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

Calls add two more rules, in the next two sections.

## What a call's result borrows

**A call's result borrows what the call was given** ([02](../spec/02-views-and-dependencies.md#rule-3-call-results)). The caller never looks inside the function. It reads the signature, and assumes the result borrows what it could reach:

- each argument passed borrowed or `mutable`, `self` included, with one exception (next);
- everything those arguments carry;
- what each `owned` argument carries, but not the argument itself, which the callee now owns.

```swift
func longest(_ lines: Span<StringView>) -> StringView { ... }

let title = longest(lines.span)           // borrows 'lines', and what 'lines' carries: 'source'
source.append("\n")                       // error: 'source' is borrowed by 'title' (used below)
log(title)
```

**A `Span`, `StringView` or number argument lends only what it carries, never itself, to a result made of spans and string views**, whether the argument is a variable or a temporary ([02](../spec/02-views-and-dependencies.md#shallow-values)). Such a result, or a list or struct of them, can point only where the argument points, never into the argument's own bytes. So `grid.row(y + 1)` borrows `grid` alone. A `MutableSpan` is no such argument, since it is move-only.

## Storing views through a `mutable` argument

**After a call, a `mutable` argument of a scoped type takes on what the other arguments borrow.** The spec calls this **absorption** ([02](../spec/02-views-and-dependencies.md#rule-4-absorption)). It is how `lines` learns, in the opening example, that it borrows `source`:

```swift
var lines = List<StringView>()            // holds views, so it is scoped
splitLines(source.view, into: &lines)     // 'lines' takes on what 'source.view' carries: 'source', shared
```

The signature can't say whether `splitLines` stores views of `text` into `out`, so the caller assumes it does. The same rule covers these cases:

- **`self` in a `mutating` method absorbs too**, so `names.append(source.view[0..<5])` makes `names` borrow `source`.
- **Only a scoped argument absorbs.** A `List<Int>` holds no views, so it takes on nothing.
- **Another `mutable` argument lends what it carries, not itself.** Take a lexer that views the script's text, and a `mutating` method `lex`. After `lexer.lex(into: &tokens)`, `tokens` holds views of the text the lexer reads. It doesn't borrow `lexer`, so the lexer can move on while `tokens` is used.

### What the function may keep

**A function can return or store only what its caller lent it** ([02](../spec/02-views-and-dependencies.md#rule-5-the-callee-side)). This is the other half of the contract: the caller trusts the signature, and the compiler holds the body to it. A function's locals are its own, so no view of one may leave it:

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

Inside `splitLines`, every line stored into `out` is a range of `text`, which the caller lent, so the body passes. Neither side needs an annotation.

## A result that borrows one argument: `where`

**A `where` clause can narrow what a result borrows** ([02](../spec/02-views-and-dependencies.md#precise-dependencies-opt-in)). By default a result borrows what every argument lends, even one the function only reads. A parser hits this when it looks a token up in a symbol table, then moves its lexer on. Here the lexer owns the script's text, so a token's text borrows the lexer itself:

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

The key is only compared, never kept. Say so, and the result borrows the table alone:

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

Each item of the clause names a subject, `return` or a `mutable` parameter, and what that subject borrows:

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

**A view of a temporary can't outlive its statement** ([02](../spec/02-views-and-dependencies.md#temporaries)). A value that no binding holds, such as a call's result, is a temporary. It is destroyed at the end of the statement that made it:

```swift
let text = try readText("arena.script").view    // error: the String dies with this statement, and 'text' is used below
log(text)
```

Name the value, and it lives to the end of its scope:

```swift
let source = try readText("arena.script")       // the binding owns the String
let text = source.view                           // fine
log(text)
```

The condition of an `if`, `guard` or `while` counts as a statement of its own, so its temporaries are gone before the body runs. A `for` loop is an exception: it keeps the temporaries of its sequence until the loop ends.

**A temporary span or string view doesn't hold its result to the statement.** In `splitLines(source.view, into: &lines)`, `source.view` is a temporary too, yet `lines` outlives it. By the rule for spans and string views ([above](#what-a-calls-result-borrows)), the view lends only what it carries: `source`. So `source.view[0..<5]` borrows `source` as well, not the temporary view.

## Staying valid after a parameter changes: `outlives`

**`outlives` says that a subject borrows what a parameter carries, but not the parameter itself**, so the subject stays valid after that parameter changes or is gone ([02](../spec/02-views-and-dependencies.md#staying-valid-after-a-parameter-moves-on-outlives)). One case is copying views from one list into another:

```swift
func copyAll(from src: List<StringView>, into dst: mutable List<StringView>)
    where dst outlives src { ... }

copyAll(from: words, into: &kept)         // 'kept' borrows what 'words' carries: 'source'
words.append("eof")                       // fine: without the clause, 'kept' would borrow 'words' itself
use(kept)
```

In general, the compiler accepts `outlives x` only when nothing `x` carries can be changed through `x` or end with it. A `Span` or a `List<StringView>` qualifies. A `MutableSpan` doesn't, since it could change the elements under the views it handed out. The spec adds one more case, for a result moved out of `x`, as `popLast()` moves an element out of a list.

**This is also why a `for` loop can collect views of a collection's elements.** A collection's iterator declares its `next()` `where return outlives self`, so each element borrows the collection, not the iterator:

```swift
var names = List<StringView>()
for entry in table.entries { names.append(entry.name.view) }   // 'names' borrows 'table'
use(names)                                                     // fine: the loop's iterator is gone
```

## When a view must live longer

**A span or string view can't be kept past the scope that lent it, so long-lived state keeps something else.** Pick by what the data is:

- **A handle.** An element of a pool is named by a `Handle<T>`: a small copyable index, checked at each use, which reads `nil` once the element is removed ([Handles and objects](05-handles-and-objects.md)).
- **A `Slice<T>`.** A range of a buffer held by a `Shared` is named by a `Slice<T>`: a checked view that can be stored anywhere, and reads `nil` once the buffer is gone ([Memory and allocators](06-memory-and-allocators.md)).
- **An owning copy.** Small data can simply be copied. `String("\(word)")` builds a `String` that owns its text, so it isn't scoped and can go anywhere.

A handle or a slice costs a check at each use, and a copy allocates once. Each is written out, so you see the cost where you pay it.

## In the spec

- [02 Scoped values](../spec/02-views-and-dependencies.md#scoped-values): the scoped types, where a scoped value can go, and `~Scoped` in generic code.
- [02 Dependencies](../spec/02-views-and-dependencies.md#dependencies): the six rules. Rules 1 and 2 fill a view's set, rule 3 gives a call's result its set, rule 4 is absorption, rule 5 is what a function may return or store, and rule 6 covers accesses to objects and slices.
- [02 Shallow values](../spec/02-views-and-dependencies.md#shallow-values): which arguments lend only what they carry, and to which results.
- [02 Temporaries](../spec/02-views-and-dependencies.md#temporaries): full statements, and the temporaries that loops keep.
- [02 When destroying a value counts as using it](../spec/02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it): which values keep what they borrow until they are destroyed.
- [02 Precise dependencies](../spec/02-views-and-dependencies.md#precise-dependencies-opt-in): every form of `where` item, and naming a field of a parameter or a result.
- [02 `outlives`](../spec/02-views-and-dependencies.md#staying-valid-after-a-parameter-moves-on-outlives): when the compiler accepts it, and values moved out of an owner.
- [04 Collections and strings](../spec/04-types.md#collections-and-strings): the views beside the owning collections, and how strings are indexed.
- [06 Long-lived views](../spec/06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers): `Slice<T>` and the buffers it views.
