# Collections and iteration

[04 · Types](../04-types.md)

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
- `Name`;
- the object pointers;
- `Slice`, whose `read()` and `lock()` begin the dynamic accesses the spans they return hold ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-6-dynamic-accesses)).

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
| `Name` | no | 64-bit interned hash of a text (below) |

**A `Name` is the 64-bit hash of a text, interned with the text, and compares by its hash alone** ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)). It is made only from a text:

- a string literal of type `Name` hashes at compile time, as `Name(s)` does for a `const` string;
- `Name(s)` of any other string, and `Name(interning: s)`, intern at run time, copying the text into `.system` memory whatever the current allocator is.

A `Name`'s `text` is a `StaticString`, since interned text is never freed. Every `Name` the build makes at compile time, by a literal, a `const` or a compile-time evaluation, is in the interner with its text from startup.

**No two texts share a `Name`**, since two that did would compare equal. A build in which two constant names would share one fails. At run time, `Name(s)` panics when another text already has `s`'s hash or interning runs out of memory, and `Name(interning: s)` returns `nil` in both cases.

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

**Interpolation writes into a sink.** An interpolated literal, such as `"hp \(hp)"`, evaluates its segments in order, as a call's arguments are evaluated ([01](../01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)), and borrows each. Its value is a scoped value of a type the compiler builds. That type is `Formattable`: it writes its text and each segment in turn into the sink it is given. Every segment's type must be `Formattable` too, as the number types, `Bool`, the string types and `Name` are:

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
let jump: Name = "jump"                   // hashed at compile time
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
| `ExpressibleByStringLiteral` | `init(stringLiteral text: StaticString)` | `StaticString`, `StringView`, `Name`, `String` |
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
- no pointer but a `StaticString` or `StaticSpan`.

`Name`, `Simd`, an `[N of T]` or `InlineList` of such values, and `std.math`'s `Vec3` and matrices qualify. Each evaluation takes a new copy of the bytes, as a `const` of a copyable type is taken ([01](../01-values-and-ownership/moving-values-out.md#constants)). So a `Name` literal costs nothing at run time.

**Any other literal runs its initializer on each evaluation**: a `List`'s allocates from the current allocator, and a `String`'s only records it. Whether or not a literal converts, when its initializer can run at compile time, a precondition it breaks on constant elements is a compile error.

**`true` and `false` are only `Bool`, and `nil` only an optional.**

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
    associatedtype MutableIterator: IteratorProtocol   // its Element is an exclusive view: MutableRef<T>, MutableSpan<T>, …
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

**A sequence that is a place is iterated where it is.** Such a place is a variable, a stored field, or a `read` or `modify` projection such as `.value`. Anything else, such as `a.enumerated()`, is a whole value. It is moved into a hidden `var` that lives until the loop ends. So is every temporary in the sequence expression, each into its own, in evaluation order. An adaptor in a hidden local keeps its collection borrowed for the whole loop:

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

**Which elements outlive the iteration follows from the dependency rules** ([02](../02-views-and-dependencies/dependency-rules.md#dependencies)):

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
var lives = &particles.life                      // MutableSpan<Float>
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
- **A receiver that is a place picks the `mutating` form**, or, where a shared form exists too, the one its access context picks (above). A place here is a variable, a stored field even of a temporary, or a `read` or `modify` projection.

So `s.split(at: m)` on a `MutableSpan` lends two halves that depend on `s` exclusively. `(consume s).split(at: m)` hands them over, carrying only what `s` carried, by rule 3 ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#rule-3-call-results)). A shared `Span`'s `split(at:)` is declared `where return outlives self`, so it needs no pair.
