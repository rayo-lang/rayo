# Collections and iteration

[04 · Types](../04-types.md)

Rayo has several ways to group values. Tuples and fixed-size arrays hold their elements inside the value itself. Collections such as `List` own storage that can grow, while views such as `Span` borrow elements from another owner. Ranges and iterators let code walk these groups without changing what owns them.

## Tuples, ranges and arrays

```swift
let pair: (Int, Float) = (3, 0.5)
let stats: (hp: Float, armor: Float) = (hp: 100, armor: 20)
let (count, weight) = pair                   // destructuring
for i in 0..<count { … }                     // a counted loop
let w: [4 of Float] = [0.1, 0.2, 0.3, 0.4]   // an Array<Float, 4>: four Floats, stored inline
var grid: [64 of Int] = .init(repeating: 0)  // every element is given
let locks: [8 of Mutex<Int>] = .init(generating: { _ in Mutex(0) })   // one call per index, for a move-only type
```

**Tuples may be labeled, and are laid out as a struct of their elements** ([Structs](structs.md#structs)). A one-element tuple is labeled or written with a trailing comma, `(x,)` of type `(Int,)`, since `(x)` is just `x`.

**Ranges are copyable values**, bounded at both ends or at one: `0..<n`, `a...b`, `..<n`, `...b` and `i...`.

**An array, `Array<T, N>`, written `[N of T]`, is `N` values of `T` stored inline**, with no heap allocation, and is copyable when `T` is. It is a language type, and what an array literal makes when nothing asks for another type ([below](#literals)).

**Its length is part of its type, so every element is given when it is made**, in one of these ways:

- by a literal of exactly `N` elements;
- by `.init(repeating:)`, which copies one copyable value into every element;
- by `.init(generating:)`, which calls a closure once per index, in order, and takes each result it returns, so it serves a move-only `T` too.

Written `[_ of T]`, an array type takes its count from the initializer.

**An array's elements are laid out end to end**, each at `index × stride`, where a type's **stride** is its size rounded up to its alignment. `N` is at least 0, and `N` times `T`'s stride fits in an `Int`, checked where both are known, as for `Simd` ([SIMD and math](numbers-and-math.md#simd-and-math)).

## Collections and strings

**Rayo separates collections that own their elements, like `List`, from views that borrow elements something else owns, like `Span`**, which are scoped ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)):

```swift
var names = List<String>()                // owns its buffer: move-only, allocated through an allocator
names.append("grunt")
names.append("brute")
let all: Span<String> = names.span        // a view: borrows the list's elements
let firstTwo = names[0..<2]               // also a Span
```

**The table below mixes language types and std's. These rows are language types:**

- the scoped views `Span`, `MutableSpan` and `StringView`;
- the immortal `StaticSpan` and `StaticString`;
- the object pointers;
- `Slice`, whose `read()` and `lock()` begin the dynamic accesses the spans they return hold ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)).

The other rows, such as the owning collections and `Handle`, are std's ([11](../11-compilation-model.md#what-the-spec-defines)), except `SoA<T>`, which is builtin ([Struct of arrays: `SoA<T>`](data-layout.md#struct-of-arrays-soat)).

**Every owning collection is move-only.** A copy of a `List`'s or a `Map`'s bytes would be a second owner of its buffer ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types)). Each one that allocates carries an allocator ([06](../06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator)).

| Type | Owning? | Notes |
| --- | --- | --- |
| `List<T>` | yes | Growable, with the allocator it came from ([06](../06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator)) |
| `Span<T>`, `MutableSpan<T>` | no (scoped) | ptr + count; `list.span`, `list[a..<b]` |
| `StaticSpan<T>` | no (immortal) | ptr + count into immortal data, copyable and unscoped ([09](../09-compile-time/attributes-and-runtime-data.md#staticspan-views-of-immortal-data)) |
| `Map<K, V>`, `Set<T>` | yes | Hash map and set |
| `InlineList<T, N>` | yes | Growable up to `N` elements, stored inline; never allocates |
| `Pool<T>`, `Handle<T>` | yes / no | Slot map over densely packed elements: dense iteration, elements move on removal ([03](../03-handles-and-objects.md#pools-and-handles)) |
| `StablePool<T>` | yes | Stable and pinnable element addresses |
| `UniquePointer<T>`, `WeakPointer<T>` | yes / no | An object on one thread, with checked weak pointers to it ([03](../03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)) |
| `Shared<T>`, `LocalShared<T>`, `WeakShared<T>` | yes / yes / no | Reference-counted pointers to a value that many places hold, and checked weak links to a `Shared` one ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)) |
| `Slice<T>` | no | Checked long-lived view into a buffer behind a `Shared` ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)) |
| `SoA<T>` | yes | Struct-of-arrays storage for any struct or tuple type `T` ([Struct of arrays: `SoA<T>`](data-layout.md#struct-of-arrays-soat)) |
| `String` | yes | UTF-8 bytes, allocator |
| `StringView` | no (scoped) | ptr + byte count; one made from a string literal views its immortal bytes, so it borrows nothing |
| `StaticString` | no (immortal) | Text in immortal data, with its length and a NUL after it, copyable and unscoped: a literal, text from the `Name` interner, or a `const` `String`'s `staticString` ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)) |
| `Name` | no | Interned text, pointer-sized: compared without reading the text, and hashed by a hash stored with it (below) |

**A `Name` is interned text: each text has exactly one `Name`, so two `Name`s are equal exactly when their texts are** ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)). Equal texts give the same `Name` wherever and on whichever thread they are interned, and different texts never do. So `==` compares only the `Name`'s own pointer-sized value, never its text, and no two texts can collide. A compiler's keywords, the keys a config schema declares and a protocol's field names compare this way, as identifiers rather than bytes:

```swift
let jump: Name = "jump"                   // a literal: interned by the build, so no code runs
assert(Name(String("jump")) == jump)      // interned at run time: finds the literal's entry
if action == jump { player.jump() }       // compares one pointer-sized value, never the text
log("pressed \(jump.text)")               // the text, as a StaticString
```

**A `Name` hashes a hash of its text stored with it, never its address.** The build computes an entry's hash when it makes a literal's entry, and the interner computes it at run time. So the hash comes from one fixed function of the text alone, which the build and the interner share, and which gives the same value at both stages whatever `Hasher` does. Its algorithm is the library's choice, but it gives one value for a given text at every stage of one build. A `Name`'s `hash(into:)` feeds that stored value to the `Hasher`, so a `Name` hashes as an integer key does ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)).

**`Name(s)` interns `s` at run time, from any thread.** It returns the `Name` that `s`'s text already has, or copies the text into `.system` memory, whatever the current allocator is, and makes a new one. `Name(s)` ends the program when that copy can't be allocated, as a plain allocating operation does, and `Name(interning: s)` returns `nil` instead ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)).

**Interned text lives for the rest of the program**, since every copy of a `Name`, wherever it was stored, must still resolve to its text. So a `Name`'s `text` is a `StaticString` ([09](../09-compile-time/attributes-and-runtime-data.md#staticspan-views-of-immortal-data)). That suits identifiers drawn from a set the program defines, such as a compiler's keywords, the keys a config schema declares or the actions a game binds. It doesn't suit text from outside the program, such as user input or a file, where each new text would grow the interner for good.

**`Name(existing: s)` looks `s` up and never interns it.** It returns the `Name` that `s`'s text already has, or `nil` for text never interned. So a program matches outside text against the names it defines without growing the interner:

```swift
if let key = Name(existing: line.key), key == jump { … }   // a key read from a file: looked up, never interned
```

**Code that must free what it interns keeps its own interner**, an owning value whose storage comes from an allocator or an arena. It holds a `List` of the texts, and a `Map` from each text to an id of the interner's own type, typed as a `Handle<T>` is by its element, so ids from two kinds of interner don't mix. Its ids compare as cheaply as a `Name`, and resolve back to text through the interner that made them. Destroying the interner, or resetting its arena, frees every text at once.

**A `Name` is copyable and unscoped, and it is `Sendable` and `Frozen`.** std declares `unsafe Sendable` and `unsafe Frozen` on it, since its value names immortal interned text, which nothing writes and every thread may read ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable), [06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)).

**`==`, hashing, `text` and `Name(existing:)` are `@noalloc`** ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)), so code that can't allocate still compares names, looks them up and reads their text. Only interning a new text allocates. `format(into:)` allocates nothing of its own either: it writes the text to its sink, and whether that write allocates is the sink's concern.

**A string literal of type `Name` is interned by the build, so it costs nothing at run time.** The build makes one entry for each text it converts to a `Name` literal in checked code, merged across modules, and freezes it into read-only data. A literal is the `Name` of its text's entry, so it converts at compile time and is `@noalloc` ([Interned literals](#interned-literals)). So it may be a `const`, an attribute argument or part of a `static if` condition. std's interner holds every such entry before any code can intern at run time, so a literal and `Name("jump")` give the same `Name`.

### Strings

**A string is UTF-8 bytes, and formatting writes straight to wherever the text is going:**

```swift
log("hp \(hp)")                           // written into the log's sink: no allocation
"pos \(p.x), \(p.y)".format(into: &buf)   // written into 'buf': no allocation
let label = String("hp \(hp)")            // builds a new String: allocates, visibly
let bad: String = "hp \(hp)"              // error: an interpolated literal is never a String
for g in label.graphemes { … }            // user-perceived characters, through an explicit view
```

**Strings are indexed by byte offset.** Unicode scalars and graphemes are explicit views, `s.scalars` and `s.graphemes`. A range of a string or string view must start and end on Unicode scalar boundaries, or taking it panics, so every string holds whole UTF-8 sequences ([10](../10-errors-and-safety/panics.md#what-panics)).

**Every string literal is null-terminated**, so `"abc".cString` passes to C at no cost. `s.cchars` views any string's bytes as a `Span<CChar>` without a terminator, for C functions that take a pointer and a length.

**Interpolation writes into a sink.** An interpolated literal, such as `"hp \(hp)"`, evaluates its segments in order, as a call's arguments are evaluated ([01](../01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)), and borrows each. As the message of `fatalError`, `precondition` or `assert`, it is evaluated only when the call panics ([10](../10-errors-and-safety/panics.md#messages)). Its value is a scoped value of a type the compiler builds. That type is `Formattable`: it writes its text and each segment in turn into the sink it is given. Every segment's type must be `Formattable` too, as the number types, `Bool`, the string types and `Name` are:

```swift
protocol TextSink { mutating func write(_ text: StringView) where self borrows static }
protocol Formattable { func format(into sink: mutable some TextSink) where sink borrows static }
```

**A sink keeps only copies of the text it is given** ([02](../02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in)). So a format may write a view of its own stack buffer, and a sink takes on no borrow of the temporaries an interpolated literal formats.

**Interpolation itself allocates nothing.** A function that takes a `Formattable`, as `log` does, writes the text where it is going, and `String(…)` allocates visibly. An interpolated literal has the type the compiler builds for it whatever its context, since no literal protocol takes interpolation. So assigning one to a `String` is an error, and `String("hp \(hp)")` builds the `String`.

### Literals

**A literal has no type until something expects one**, so `[1, 2, 3]`, `"jump"` and `0.5` become whatever their context asks for:

```swift
let v: Vec3 = [1, 2, 3]                   // a Vec3: exactly 3 elements
let mask: LayerMask = [.player, .enemies] // a user type that conforms: any number of layers
let jump: Name = "jump"                   // interned by the build: no cost at run time
let lo: Int8 = -128                       // fits: the '-' is checked with the literal
names.append("grunt")                     // a String that uses the literal's bytes: no allocation
let xs = [3, 4, 5]                        // no context: a [3 of Int], stored inline
let ys: List<_> = [3, 4, 5]               // a List<Int>, from the annotation
let zs = [3, 4, 5] as List<_>             // the same, from 'as'
spawnAll([a, b])                          // spawnAll takes a List: the same as spawnAll(List([a, b]))
let bad: Vec3 = [1, 2]                    // error: a Vec3 literal needs 3 elements
```

**A type takes a literal by conforming to one of the literal protocols**, whose initializer receives the literal:

| Protocol | Requirement | Conforming types |
| --- | --- | --- |
| `ExpressibleByArrayLiteral` | `init<let N: Int>(arrayLiteral elements: owned [N of ArrayLiteralElement])` | `Array`, `Simd`, `InlineList`, `List`, `Set`, `std.math`'s `Vec3` and matrices |
| `ExpressibleByDictionaryLiteral` | `init<let N: Int>(dictionaryLiteral pairs: owned [N of (Key, Value)])` | `Array` of `(Key, Value)` pairs, `Map`, user types such as a fixed lookup table |
| `ExpressibleByStringLiteral` | `init(stringLiteral text: StaticString)` | `StaticString`, `StringView`, `String` |
| `ExpressibleByInternedLiteral` | `unsafe init(internedLiteral entry: StaticSpan<InternedEntry>)`, and an entry per text ([below](#interned-literals)) | `Name` |
| `ExpressibleByIntegerLiteral` | `init(integerLiteral value: IntegerLiteralType)` | every number type |
| `ExpressibleByFloatLiteral` | `init(floatLiteral value: FloatLiteralType)` | `Half`, `Float`, `Double` |

**A literal becomes the type its position expects, wherever that type conforms**: in an annotation, after `as`, and as an argument, a `return` value or the right side of an assignment. So `spawnAll([a, b])` passes the `List` that `[a, b]` builds, as `spawnAll(List([a, b]))` would, and that `List` allocates from the current allocator ([06](../06-memory-and-allocators/allocator-basics.md#the-current-allocator)). In an annotation or after `as`, `_` stands for what the literal fills in, as in `List<_>`.

**In `@noalloc` code, a literal converts only where that can't allocate** ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)). That holds when either of these does:

- its initializer is `@noalloc`, as those of the number types, `Array`, `Simd`, `InlineList`, `StaticString`, `StringView`, `String` and `std.math`'s `Vec3` and matrices are;
- its literals convert at compile time (below), as `Name`'s do.

So a `List`, `Set` or `Map` literal is an error there.

**std's `String` takes a literal without allocating.** It records the current allocator, as every `String` does, and is checked against it at each open like any other ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)). But it uses the literal's immortal bytes until the first call that writes or grows it, which copies them into a buffer from that allocator.

**An array literal's elements arrive inline**, as an owned `[N of Element]` whose count is known at compile time, never as a heap buffer. So a type refuses a count it can't hold at compile time, through `static if` and `static error` ([09](../09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation)): `Simd<T, N>` takes exactly `N` elements, `Vec3` exactly 3 and `InlineList<T, 8>` at most 8. Passed where an `[N of T]` with an unbound `N` or `T` is expected, as for `List([1, 2, 3])`, a literal binds `N` to its count and `T` as it does with no context.

**An integer or float literal is checked against the type it becomes.** An integer literal must fit the conformer's `IntegerLiteralType`, at compile time. A float literal is rounded once, to its `FloatLiteralType`, which is `Half`, `Float` or `Double`. A prefix `-` applied directly to a literal, where an operand begins, is checked with it as one value. So `-128` fits an `Int8`, although `128` alone doesn't, while `n-1` still subtracts. A postfix member applies to the literal first, so `-128.abs` is `-(128.abs)`.

**With no context, a literal has a default type:**

- an integer literal is an `Int`, and a floating-point literal a `Double`;
- a string literal is a `StaticString`;
- a dictionary literal is an `[N of (K, V)]`;
- an array literal is an `[N of T]`, whose `T` is the type of its typed elements, which must agree.

**When every element is a literal, the elements take one default together:**

- for number literals, `Double` if any is a floating-point one, and `Int` if none is;
- for literals of one other kind, that kind's default, so `["a", "b"]` is a `[2 of StaticString]`.

Literals of different kinds, such as `1` and `"a"`, are an error. An empty `[]` or `[:]` needs a context.

**A literal of constants converts at compile time.** A literal of constants is one whose elements, at any depth, are literals or `const`s. It converts when its initializer can run at compile time ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)) and the value it builds owns nothing outside its own bytes:

- no allocation;
- no object;
- no `Synchronized` value;
- no `Allocator` id but `.system`;
- no pointer but one into immortal data, as a `StaticString`, a `StaticSpan` or a `Name` holds.

`Name`, `Simd`, an `[N of T]` or `InlineList` of such values, and `std.math`'s `Vec3` and matrices qualify. Each evaluation takes a new copy of the bytes, as a `const` of a copyable type is taken ([01](../01-values-and-ownership/moving-values-out.md#constants)). So a `Name` literal costs nothing at run time.

**Any other literal runs its initializer on each evaluation**: a `List`'s allocates from the current allocator, and a `String`'s only records it. Whether or not a literal converts, when its initializer can run at compile time, a precondition it breaks on constant elements is a compile error.

**`true` and `false` are only `Bool`, and `nil` only an optional.**

#### Interned literals

**A type interns its string literals with the build's help by conforming to `ExpressibleByInternedLiteral`**, as std's `Name` does. The build makes each text's entry once, and the type's interner starts out holding them all. So a literal costs nothing at run time, and still names the entry that interning its text at run time finds:

```swift
protocol ExpressibleByInternedLiteral {
    associatedtype InternedEntry: Frozen & TrivialFree & Sendable         // one per distinct text
    static func internedEntry(for text: StaticString) -> InternedEntry     // run by the compiler, once per distinct text
    @noalloc unsafe init(internedLiteral entry: StaticSpan<InternedEntry>) // the entry the build bound for the literal
    unsafe static func internLoaded(_ entries: StaticSpan<InternedEntry>,  // code loaded after startup (below)
                                    binding bound: MutableSpan<StaticSpan<InternedEntry>>) -> Void!AllocError
}
```

- **One table per type.** The table holds an entry for each text the build converts to a `T` literal in checked code, anywhere in the program. The build runs `internedEntry(for:)` once per text and freezes the results into one table in read-only data, so equal texts in different modules share one entry.
- **Entries are freezable.** `InternedEntry` is `Frozen`, `TrivialFree` and `Sendable`, and the build checks the rest of the freezable test on each entry it makes ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).
- **A stray entry never becomes a value.** `internedEntry(for:)` is safe to call from anywhere, since it only builds an entry from a text and touches no interner. An entry built that way never becomes a value of the type, since only `unsafe` code calls `init(internedLiteral:)`, promising the entry is the one the build bound (below). std's `Name` also keeps its entry's fields private.
- **The table exists only at run time.** `T.internedLiterals`, a `StaticSpan<T.InternedEntry>`, views it. Compile-time code can't read it, and `static if` can't test it, since what it holds depends on every literal the build checks, compile-time code's included.
- **Each literal is built at compile time.** The `@noalloc` `init(internedLiteral:)` receives the literal's element of the table, and must be able to run at compile time, so every such literal converts at compile time ([above](#literals)).
- **Its caller promises the entry.** `init(internedLiteral:)` is `unsafe`: its caller promises that the span is the entry the build bound for that literal, since an entry from anywhere else would give its text a second value. The call the build makes for a literal carries that promise itself, so a literal needs no `unsafe` in source, in a `@safe` module too ([10](../10-errors-and-safety/unsafe-code.md#what-needs-unsafe)).
- **The table seeds the interner.** std's `Name` interner reads `Name.internedLiterals` in its own global's initializer. Interning reads that global, so the initialization checks keep any code from interning before the table is in it ([07](../07-concurrency/global-state.md#initialization-at-startup)).

**A conformer is a type that can declare a static stored `let`, and doesn't also conform to `ExpressibleByStringLiteral`.** It keeps its interner in a static stored `let`. So it is none of the places 07 lists where one declaration stands for many instances, such as a generic type, a type nested in one or a type local to a generic function ([07](../07-concurrency/global-state.md#global-state)). A type that conforms to both protocols is a compile error, since a string literal of it would have two meanings.

**Code loaded after startup binds its literals to entries before it runs.** The spec defines no way to load code after startup ([11](../11-compilation-model.md#what-the-spec-defines)). It fixes only what a layer that does so, such as a hot reloader, builds on:

- **Each literal reaches its entry through a symbol** keyed by the type and the text, and so does each frozen value that holds one. In the program the build links, the symbol names the text's element of the table, and a loader may bind it to an existing entry instead.
- **`internLoaded(_:binding:)` takes the new code's entries before that code runs.** The conformer interns each one, and stores in `bound[i]` the entry that `entries[i]`'s text binds to: `entries[i]` itself for a new text, or the entry the text already has. The loader binds each symbol to that entry, so equal texts still give one `Name`.
- **It is `unsafe`**, since its contract assumes what only the loader knows: that `entries` is the new code's table, and that the loader binds each symbol through `bound` as placed ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)).
- **It fails with `AllocError` when the interner can't grow**, so the loader can refuse the code. std's `Name` implements it with its interner.
- **Loaded code shares the program's hash function.** Its entries carry hashes its own build computed, so it must come from a build whose function for an entry's hash is the running program's. A loader that can't confirm this refuses the code.

### Iteration

**A `for` loop borrows each element where it is, so iterating never copies:**

```swift
var total: Float = 0
for e in enemies { total += e.hp }                        // e is each element, borrowed shared
for e in &enemies { e.hp -= 1 }                           // e is each element, borrowed mutably
for (i, e) in &enemies.enumerated() { … }                 // i is an Int, e a mutable borrow
for (v, f) in zip(&vels, forces) { v += f * dt }          // two sequences in lockstep
```

```swift
protocol Sequence { associatedtype Iterator: IteratorProtocol; func makeIterator() -> Iterator }
protocol IteratorProtocol { associatedtype Element; mutating func next() -> Element? }   // may lend
protocol SharedIterator: IteratorProtocol {     // elements outlive the iteration (02)
    mutating func next() -> Element? where return outlives self
}
protocol Collection: Sequence where Iterator: SharedIterator { var count: Int { get } }   // what generic algorithms take

protocol MutableSequence {                      // what 'for x in &s' iterates
    associatedtype MutableIterator: IteratorProtocol   // a collection's yields exclusive views, such as MutableRef<T>; a Receiver's, owned items
    mutating func makeMutableIterator() -> MutableIterator
}

protocol ConsumingSequence {                    // what a loop over a whole value takes
    associatedtype ConsumingIterator: IteratorProtocol
    consuming func makeConsumingIterator() -> ConsumingIterator
}
```

**A collection's shared and mutable iterators yield views of its elements, and its consuming iterator yields the elements themselves:**

- its iterator yields `Borrow<T>`, a copyable, scoped shared view of one element;
- its mutable iterator yields `MutableRef<T>`, a move-only exclusive one, a one-element `MutableSpan`;
- its consuming iterator yields each `T` itself.

A pattern binds through the view's `value`, so move-only elements iterate like any others.

**A sequence that is a place is iterated where it is.** Such a place is a variable, a stored field, or a place property's place, such as `.value`. Anything else, such as `a.enumerated()`, is a whole value. It is moved into a hidden `var` that lives until the loop ends. So is every temporary in the sequence expression, each into its own, in evaluation order. An adaptor in a hidden local keeps its collection borrowed for the whole loop:

```swift
for (i, e) in &makeEnemies().enumerated() { … }       // the new list is a hidden mutable local, and so is its adaptor
```

**Each element is bound in place when it lives in the collection, and owned when the iterator hands it out as a value of its own** ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns)). A loop runs as a `while` over an iterator that its form picks, where `S` is what is iterated:

| Loop over | Iterator | Each pass |
| --- | --- | --- |
| `&s` | `var it = S.makeMutableIterator()` | `while var r = it.next()`: bind the pattern to `r′`, then run the body |
| a whole value whose type conforms to `ConsumingSequence` | `var it = S.makeConsumingIterator()` | `while let b = it.next()`: bind the pattern to `b′`, then run the body |
| anything else | `var it = S.makeIterator()` | `while let b = it.next()`: bind the pattern to `b′`, then run the body |

- **A loop over `&s` holds `S`, and through it the collection, exclusively.** The `&` selects this form, and is required to change elements, as it is in any binding ([01](../01-values-and-ownership/bindings.md#lending-a-place-for-change)).
- **A loop over a whole value whose type conforms to `ConsumingSequence`**, such as a call result or `consume x`, gives `S` to the iterator. So a loop over `consume jobs` hands each job over, and the iterator's `deinit` destroys the elements a `break`, `return` or `throw` leaves. `[N of T]` conforms to `ConsumingSequence`, as std's owning collections do.
- **An element that lives in the collection is bound in place**: `b′` is `b.value` for a `Borrow`, and `r′` is `&r.value` for a `MutableRef`. So a loop without `&` can't change the elements that live in `s`, and changing one is a compile error ([01](../01-values-and-ownership/bindings.md#lending-a-place-for-change)).
- **Any other element is a value the iterator hands out**, such as a range's `Int` or a chunk. Then `b′` is `consume b`, `r′` is `consume r`, and the loop variable owns it for the iteration, as `i` does below.

```swift
for i in 0..<n { ids.append(i) }              // 'i' owns each Int for its iteration
for (h, e) in &pool.entries { … }             // 'e' is bound in place, and 'h' owns its own handle
for e in &enemies where e.hp > 0 { … }        // the body runs only where the condition holds
```

**The pattern binds part by part, and what each part binds decides whether it can change:**

- **An element bound in place is read-only through a `Borrow` or a shared row, and changeable through a `MutableRef` or an exclusive row.** A loop over `&s` hands out the exclusive kind, and so does a `zip` for each `&` argument. So a loop that changes its elements writes `&` on the sequence and nothing on the pattern, as a loop that reads them writes nothing either.
- **A value the iterator hands out is owned by its part**, such as a range's `Int`, a handle or a chunk. It is read-only unless the part is written `var`, as for any binding of a value.
- **`var` on a part bound in place is a compile error**, since the element's view already says whether it changes.

So the `pool.entries` loop above binds `e` in place, where it can change it, and gives `h` its own handle ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). A `zip` with `&` arguments hands out `MutableRef` parts itself, so the `zip` loop at the top of this section needs no `&` of its own.

**A `where c` after the sequence runs the body as `if c { body }`**, with the pattern bound, as in the `enemies` loop above.

**`while` takes conditions as `if` does** ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns)), and narrows as `if` does ([Narrowing](enums.md#narrowing)). `repeat { … } while c` tests `c` after each pass. A label, as in `outer: for row in grid`, lets a nested loop's `break outer` or `continue outer` name that loop.

**Which elements outlive the iteration follows from the dependency rules** ([02](../02-views-and-dependencies.md#dependencies)):

```swift
var names = List<StringView>()
for s in table.entries { names.append(s.name.view) }    // fine: each element depends on 'table', not the iterator
for var chunk in &data.chunks(64) { scale(&chunk) }   // one MutableSpan<Float> at a time, owned by 'chunk'
```

**A mutable iterator lends.** Its `mutating` `next()` makes each element depend exclusively on the iterator until the next call, so two are never live at once. Keeping a chunk past its iteration, or holding two, is a compile error. `split(at:)` gives two at once.

**`zip` is builtin**, since no generic function takes a varying number of arguments with per-argument conventions. `zip(a, &b, c)` borrows `&` arguments exclusively and the rest shared, hands out tuples, and stops at the shortest, so every element is in bounds. A `zip` with an `&` argument is a move-only exclusive view whose only iteration is the consuming one. So a loop over a place holding one consumes it explicitly, and no two iterators hand out its `MutableRef`s:

```swift
for (x, y) in consume z { … }       // 'z' holds a zip with an '&' argument: its only iteration consumes it
```

### Shared, mutable and consuming forms of one method

**One name can have a shared and a mutable form, each picked by its context:**

```swift
for (i, e) in items.enumerated() { … }           // shared: (Int, Borrow<Item>) elements
for (i, e) in &items.enumerated() { … }          // exclusive: (Int, MutableRef<Item>) elements
let ages = particles.life                        // Span<Float>
log("first age \(ages[0])")
var lives = &particles.life                      // MutableSpan<Float>
lives[0] = 1
particles.life.sort()                            // only the mutable form has sort(), so it is used
```

**A type may declare a non-`mutating` and a `mutating` method or property with the same name and parameters, and each use picks one by its access context alone**, with no search. A `mutating` computed property or subscript has accessors that take `self` exclusively:

```swift
var life: Span<Float> { get { … } }                    // the shared form
mutating var life: MutableSpan<Float> { get { … } }    // the mutable form: its accessors take 'self' exclusively
```

The context is exclusive for these:

- an operand of `&` ([01](../01-values-and-ownership/bindings.md#lending-a-place-for-change));
- an assignment's target;
- a receiver only the exclusive form can serve (below).

Everywhere else it is shared, so a value of the mutable form is written with `&`, as in a result or an argument:

```swift
func lives(_ p: mutable Particles) -> MutableSpan<Float> { &p.life }   // a result of the mutable form
func cols(_ p: mutable Particles) -> Cols { Cols(life: &p.life) }      // an argument of it
```

**For a call's receiver, the least access wins.** The shared form is used when its declared result has a member that fits, so `data[0..<n].split(at: m)` splits a `Span`. The exclusive form is used only otherwise, as for `particles.life.sort()`. A binding of `&data[0..<n]` forces the exclusive form.

**A `consuming` method may share a `mutating` one's name and parameters:**

```swift
var (a, b) = s.split(at: m)             // 's' is a place: the mutating form lends two halves
var (c, d) = (consume s).split(at: m)   // a whole value: the consuming form hands them over
```

- **A receiver that is a whole value picks the `consuming` form**: a call result, a `get` accessor's or subscript's included, or `consume x`.
- **A receiver that is a place picks the `mutating` form**, or, where a shared form exists too, the one its access context picks (above). A place here is a variable, a stored field even of a temporary, or a place property's place.

So `s.split(at: m)` on a `MutableSpan` lends two halves that depend on `s` exclusively. `(consume s).split(at: m)` hands them over, carrying only what `s` carried, by rule 3 ([02](../02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)). A shared `Span`'s `split(at:)` is declared `where return outlives self`, so it needs no pair.
