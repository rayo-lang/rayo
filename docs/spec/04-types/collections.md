# Collections and iteration

[04 · Types](../04-types.md)

Rayo has several ways to group values. Tuples and fixed-size arrays hold their elements inside the value itself. Collections such as `List` own storage that can grow, and a reference to a run of elements, `&[T]`, borrows elements from whatever owns them. Ranges and iterators let code walk these groups without changing what owns them.

## Tuples, ranges and arrays

```swift
let pair: (UInt, Float) = (3, 0.5)
let stats: (hp: Float, armor: Float) = (hp: 100, armor: 20)
let (count, weight) = pair                   // destructuring a copy: both elements are implicitly copyable
for i in 0..<count { … }                     // a counted loop
let w: [4 of Float] = [0.1, 0.2, 0.3, 0.4]   // an Array<Float, 4>: four Floats, stored inline
var grid: [64 of Int] = .init(repeating: 0)  // every element is given
let locks: [8 of Mutex<Int>] = .init(each: { _ in Mutex(0) })   // one call per index, for a move-only type
```

**Tuples may be labeled, and are laid out as a struct of their elements** ([Structs](structs.md#structs)). A one-element tuple is labeled or written with a trailing comma, `(x,)` of type `(Int,)`, since `(x)` is just `x`. A tuple whose elements are all implicitly copyable is implicitly copyable too, as `pair` is ([01](../01-values-and-ownership/moves-copies-destruction.md#implicitly-copyable-types)).

**Ranges are copyable values**, bounded at both ends or at one: `0..<n`, `a...b`, `..<n`, `...b` and `i...`. A range is implicitly copyable when its bounds are, as a range of `Int`s is, since it holds only its bounds ([01](../01-values-and-ownership/moves-copies-destruction.md#implicitly-copyable-types)).

**An array, `Array<T, N>`, written `[N of T]`, is `N` values of `T` stored inline**, with no heap allocation, and is copyable when `T` is. It is never implicitly copyable, even a `[4 of Float]`, so a copy of one is always written ([01](../01-values-and-ownership/moves-copies-destruction.md#implicitly-copyable-types)). It is a language type, and what an array literal makes when nothing asks for another type ([below](#literals)).

**Its length is part of its type, so every element is given when it is made**, in one of these ways:

- by a literal of exactly `N` elements;
- by `.init(repeating:)`, which copies one copyable value into every element;
- by `.init(each:)`, which calls a closure once per index, in order, passing it the index as a `UInt`, and takes each result it returns, so it serves a move-only `T` too.

Written `[_ of T]`, an array type takes its count from the initializer.

**A literal whose count differs from `N` is a compile error**, since it would leave elements without a value, or have values with no element to hold them. The count is known when the program is checked, so no literal is checked when it runs:

```swift
let w: [4 of Float] = [0.1, 0.2, 0.3]   // error: a [4 of Float] literal needs 4 elements
```

**An array's elements are laid out end to end**, each at `index × stride`, where a type's **stride** is its size rounded up to its alignment. `N` is a `UInt`, and `N` times `T`'s stride fits in an `Int`, checked where both are known, as for `Simd` ([SIMD and math](numbers-and-math.md#simd-and-math)).

**`a.count` is `N`**, a read-only `UInt` that the type fixes. So it takes no storage in the array, and assigning it is a compile error.

### Inline array elements

**`a[i]` is element `i` of an inline array `a`, a place inside `a` as a stored field is.** No subscript accessor runs to find it: the element lies at `i × stride` from the array's start ([above](#tuples-ranges-and-arrays)). So the rules that follow a path through a stored field follow it through an element too:

- two elements at indices known to differ where the borrows are checked are disjoint, as two stored fields are ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap));
- a closure that names `a[2]` captures that element alone ([05](../05-protocols-generics-and-closures/functions-and-closures.md#capturing-places));
- a `ref let` of `a[i]`, and `&a[i]`, borrow the element where it lies ([01](../01-values-and-ownership/bindings.md#bindings)).

An inline array that holds a value holds all `N` of its elements, since no element is moved out and none is assigned before the array holds a value ([01](../01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)).

**An index is a `UInt`, so the indices of `[N of T]` run from `0` to `N - 1`.** An index known when the program is checked, an integer literal or a `const`, that lies outside `0..<N` is a compile error. Any other index is checked when the program runs, so `a[i]` panics with `index out of range` when `i` is `N` or more. That is a bounds check, on in every build, which only an `unchecked` block removes ([10](../10-errors-and-safety/checks-and-build-modes.md#unchecked-blocks)):

```swift
const edge: UInt = 64

var grid: [64 of Int] = .init(repeating: 0)
grid[63] = 1                 // fine: the last element
grid[edge] = 1               // error: index 64 is out of range for a [64 of Int]
let i: UInt = readIndex()
grid[i] = 1                  // checked when it runs: panics when 'i' is 64 or more
```

## Collections and strings

**Rayo separates collections that own their elements, like `List`, from the elements themselves, a run `[T]` that code reaches through a reference.** A reference borrows the elements from whatever owns them, and is scoped ([01](../01-values-and-ownership/references.md#references)):

```swift
var names = alloc List<String>()          // owns its buffer: move-only, allocated through an allocator
names.append(alloc "grunt")               // a String owns its text, so it is made with 'alloc' too
names.append(alloc "brute")
let all: &[String] = names                // a reference to the list's elements, which borrows 'names'
let firstTwo = &names[0..<2]              // a '&[String]' of the first two
```

**The table below mixes language types and std's. These rows are language types:**

- `[T]`, the unsized run of elements ([below](#runs-of-elements));
- the static types, such as `static &[T]` and `static &Text`, which refer only to data that lives as long as the program;
- the object pointers;
- `Slice`, whose `read()` and `lock()` begin the dynamic accesses the references they return hold ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)).

The other rows, such as the owning collections and `Handle`, are std's ([11](../11-compilation-model.md#what-the-spec-defines)), except `SoA<T>`, which is builtin ([Struct of arrays: `SoA<T>`](data-layout.md#struct-of-arrays-soat)). `Text` is std's too, and the language names it, since a string literal is a `static &Text` ([Strings](#strings)).

**Every owning collection is move-only.** A copy of a `List`'s or a `Map`'s bytes would be a second owner of its buffer ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types)). Each one that allocates is `Allocating`, so making one says `alloc`, and it carries an allocator ([06](../06-memory-and-allocators/allocator-basics.md#the-allocating-protocol)).

| Type | Owning? | Notes |
| --- | --- | --- |
| `List<T>` | yes | Growable, with the allocator it came from ([06](../06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator)); its elements are the `[T]` place `list.span`, and `&list` converts to a `&[T]` ([below](#runs-of-elements)) |
| `[T]` | no (unsized) | A run of elements, held as a `&[T]` or a `mutable &[T]`, each a pointer and a count: `&list.span`, `&list[a..<b]` |
| `static &[T]` | no (static) | A reference to elements that live as long as the program, implicitly copyable and unscoped ([02](../02-views-and-dependencies/scoped-values.md#static-values)) |
| `Map<K, V, H>`, `Set<T, H>` | yes | Hash map and set, hashed as their hashing type `H` says, by default with a seed drawn for each run ([below](#hash-maps-and-sets)) |
| `InlineList<T, N>` | yes | Growable up to `N` elements, stored inline; never allocates; never implicitly copyable, as an inline array isn't |
| `Pool<T>`, `Handle<T>` | yes / no | Slot map over densely packed elements: dense iteration, elements move on removal ([03](../03-handles-and-objects.md#pools-and-handles)) |
| `StablePool<T>` | yes | Stable and pinnable element addresses |
| `UniquePointer<T>`, `WeakPointer<T>` | yes / no | An object on one thread, with checked weak pointers to it ([03](../03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)) |
| `Shared<T>`, `LocalShared<T>`, `WeakShared<T>` | yes / yes / no | Reference-counted pointers to a value that many places hold, and checked weak links to a `Shared` one ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)) |
| `Slice<T>` | no | Checked long-lived view into a buffer behind a `Shared` ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)) |
| `SoA<T>` | yes | Struct-of-arrays storage for any struct or tuple type `T` ([Struct of arrays: `SoA<T>`](data-layout.md#struct-of-arrays-soat)) |
| `String` | yes | UTF-8 bytes, allocator; made only with `alloc`, and `&string` converts to a `&Text` ([below](#strings)) |
| `Text` | no (unsized) | A run of UTF-8, held as a `&Text`, a pointer and a byte count |
| `static &Text` | no (static) | A reference to text that lives as long as the program, implicitly copyable and unscoped: a literal, a `Name`'s text, or a reference to a `const`'s or a global `let`'s `String` ([02](../02-views-and-dependencies/scoped-values.md#static-values)) |
| `Name` | no | Interned text, pointer-sized: compared without reading the text, and hashed by its entry or by a hash stored with it (below) |

**A `Name` is interned text: each text has exactly one `Name`, so two `Name`s are equal exactly when their texts are** ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)). Equal texts give the same `Name` wherever and on whichever thread they are interned, and different texts never do. So `==` compares only the `Name`'s own pointer-sized value, never its text, and no two texts can collide. A compiler's keywords, the keys a config schema declares and a protocol's field names compare this way, as identifiers rather than bytes:

```swift
let jump: Name = "jump"                     // a literal: interned by the build, so no code runs
let typed = alloc "jump"
assert(Name(typed) == jump)                 // interned at run time: finds the literal's entry
if action == jump { player.jump() }         // compares one pointer-sized value, never the text
log("pressed \(jump.text)")                 // the text, as a static &Text
```

**A `Name`'s entry stores a hash of its text.** The build computes an entry's hash when it makes a literal's entry, and the interner computes it at run time. So the hash comes from one fixed function of the text alone, which the build and the interner share, and which gives one value for a given text at every stage of one build. Its algorithm is the library's choice, within two limits that keep anyone from finding many texts with one hash:

- it is at least 64 bits wide;
- it comes from a function with no known way to build multicollisions, sets of many texts that share one hash.

**What a `Name`'s `hash(into:)` feeds a `Hasher` depends on where the hasher's seed came from** ([Hash maps and sets](#hash-maps-and-sets)):

- **From the process seed**, it feeds the address of the `Name`'s entry. Each text has one entry, which is never freed, and a loader binds new code's literals to existing entries (below). So two `Name`s feed one address exactly when they are equal, and no two keys collide. Such a `Hasher` exists only at run time, where the address never changes.
- **From a given seed**, as under `FixedHashing`, it feeds the stored hash, which the build and the interner compute alike. So a frozen map finds its `Name` keys at run time. Texts whose stored hashes collide collide under every given seed, which the limits above make hard to arrange.

std's `Name` tells the two apart by `hasher.startsFromProcessSeed`, the one property `Hasher` exposes for it.

**`Name(s)` interns `s` at run time, from any thread.** It returns the `Name` that `s`'s text already has, or copies the text into `.heap` memory, whatever the ambient allocator is, and makes a new one. The interner's storage takes no `alloc`, since no value the code makes owns it ([06](../06-memory-and-allocators/allocator-basics.md#allocations-with-no-construction)). `Name(s)` ends the program when that copy can't be allocated, as a plain allocating operation does, and `Name(interning: s)` returns `nil` instead ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)).

**Interned text lives for the rest of the program**, since every copy of a `Name`, wherever it was stored, must still resolve to its text. So a `Name`'s `text` is a `static &Text` ([02](../02-views-and-dependencies/scoped-values.md#static-values)). That suits identifiers drawn from a set the program defines, such as a compiler's keywords, the keys a config schema declares or the actions a game binds. It doesn't suit text from outside the program, such as user input or a file, where each new text would grow the interner for good.

**`Name(existing: s)` looks `s` up and never interns it.** It returns the `Name` that `s`'s text already has, or `nil` for text never interned. So a program matches outside text against the names it defines without growing the interner:

```swift
if let key = Name(existing: line.key), key == jump { … }    // a key read from a file: looked up, never interned
```

**Code that must free what it interns keeps its own interner**, an owning value whose storage comes from an allocator or an arena. It holds a `List` of the texts, and a `Map` from each text to an id of the interner's own type, typed as a `Handle<T>` is by its element, so ids from two kinds of interner don't mix. Its ids compare as cheaply as a `Name`, and resolve back to text through the interner that made them. Destroying the interner, or resetting its arena, frees every text at once.

**A `Name` is implicitly copyable and unscoped, and it is `Sendable` and `Frozen`.** std declares `unsafe Sendable` and `unsafe Frozen` on it, since its value names immortal interned text, which nothing writes and every thread may read ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable), [06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)). It declares `ImplicitlyCopyable` too, since a copy is one pointer-sized value that names the same text ([01](../01-values-and-ownership/moves-copies-destruction.md#implicitly-copyable-types)).

**`==`, hashing, `text` and `Name(existing:)` are `@noalloc`** ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)), so code that can't allocate still compares names, looks them up and reads their text. Only interning a new text allocates. `format(into:)` allocates nothing of its own either: it writes the text to its sink, and whether that write allocates is the sink's concern.

**A string literal of type `Name` is interned by the build, so it costs nothing at run time.** The build makes one entry for each text it converts to a `Name` literal in checked code, merged across modules, and freezes it into read-only data. A literal is the `Name` of its text's entry, so it converts at compile time and is `@noalloc` ([Interned literals](#interned-literals)). So it may be a `const`, an attribute argument or part of a `static if` condition. std's interner holds every such entry before any code can intern at run time, so a literal and `Name("jump")` give the same `Name`.

### Runs of elements

**`[T]` is a run of elements: `T`s laid end to end, in storage that something else owns.** Its count isn't part of its type, so it is unsized, and code reaches it only through a reference: a `&[T]` reads the elements, and a `mutable &[T]` may change them ([01](../01-values-and-ownership/references.md#unsized-types)). Each reference is a pointer and a count ([01](../01-values-and-ownership/references.md#layout)). So one function that takes a `&[T]` serves a list, a range of one and a column alike.

**These hand out their elements as a `[T]` place**, which `&` and `mutable` lend as any place is lent ([Shared and mutable views of one collection](#shared-and-mutable-views-of-one-collection)):

- `list.span`, a place property with a `borrow` and a `mutate`;
- a range subscript, such as `list[a..<b]`, `a[..<n]` of an inline array, or `s[a..<b]` of a run itself, which is a `[T]` place with both accessors too;
- a column of an `SoA`, and a `TrailingArray`'s `elements` ([Data layout](data-layout.md#struct-of-arrays-soat)).

**A `&List<T>` converts to a `&[T]`, and a `mutable &List<T>` to a `mutable &[T]`, where the expected type asks for one** ([01](../01-values-and-ownership/bindings.md#conversions)). So a function that reads elements takes a `&[T]`, and its callers give it what they have, which is lent ([05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)):

```swift
func average(_ xs: &[Float]) -> Float { … }

average(samples)                    // a List<Float>: lent as a reference to its elements
average(samples[0..<64])            // the first 64 of them
```

**A run's members read its elements, change them where they lie, or lend parts of it.** A run is iterated through a reference to it ([Iteration](#iteration)):

| Member | What it is |
| --- | --- |
| `count` | The number of elements, a read-only `UInt` |
| `baseAddress` | The first element's address, a `*T`, which only `unsafe` code reads ([10](../10-errors-and-safety/unsafe-code.md#what-needs-unsafe)) |
| `s[i]` | Element `i`, a place with a `borrow` and a `mutate`, bounds-checked as an inline array's element is ([above](#inline-array-elements)) |
| `s[a..<b]`, and the other ranges | The elements in the range, a `[T]` place with a `borrow` and a `mutate` |
| `split(at: m)` | Shared references to the elements before `m` and from `m` on, as a `(&[T], &[T])` |
| `mutableSplit(at: m)` | A `mutating` method that lends the two halves as a `(mutable &[T], mutable &[T])`, which depends on the run exclusively |
| `sort()` | A `mutating` method that reorders the elements, where `T: Comparable` |
| `copy(from: source)` | A `mutating` method that copies in the elements of a `&[T]` of the same count, where `T: Copyable`, and panics when the counts differ |
| `reinterpret(as:)`, `mutableReinterpret(as:)` | The elements as a run of another `Pod` type ([Data layout](data-layout.md#plain-data-pod-and-bit-casts)) |
| `chunks(n)`, `enumerated()`, `zip(other)`, and their mutable forms | Sequences that hand out references to parts or elements ([below](#shared-and-mutable-views-of-one-collection)) |

```swift
var some = mutable hits[0..<4]            // a 'mutable &[Int]' of the first four hits
some.sort()                               // sorts the four where they lie
var (lo, hi) = some.mutableSplit(at: 2)   // two 'mutable &[Int]'s: 'some' stays borrowed while either is used
lo[0] = hi[0]
```

### Hash maps and sets

```swift
enum Action { case jump, fire, crouch }

const bindings: Map<Name, Action, FixedHashing> = alloc ["jump": .jump]   // frozen into read-only data
const aliases: Map<Name, Action> = alloc ["leap": .jump]                  // error: a seeded Map can't be made at compile time
let shortcuts: Map<Name, Action> = alloc ["leap": .jump]                  // fine: a global 'let', built at startup
```

**By default, `Map` and `Set` hash their keys with a seed that nobody outside the program can learn, so nobody can choose keys that collide.** A program that hashes keys from outside, such as a server reading a request's headers, would otherwise let whoever sends them pick keys that all land in one bucket. Each lookup would then walk every one of those keys, and a few thousand of them could stall the server.

**std's `Hasher` is a keyed pseudorandom function: without its seed, nobody can predict what it outputs.** SipHash-1-3 is one such function. Which one std uses is the library's choice. A `Hasher` starts from a 128-bit `HashSeed`:

```swift
struct HashSeed private init(…): ImplicitlyCopyable {   // 16 bytes; its fields are private too
    init(_ high: UInt64, _ low: UInt64)           // a given seed
    static func fromProcessSeed() -> HashSeed     // a new seed, derived from the process seed
}

struct Hasher(…) {
    init(seed: HashSeed)
    var startsFromProcessSeed: Bool { get }       // whether its seed came from fromProcessSeed()
}
```

**The process seed is a random value of at least 128 bits, which startup draws from the platform before any initializer runs** ([07](../07-concurrency/global-state.md#initialization-at-startup)). Reading it reads a random value from the platform, so it can't run at compile time ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)).

**`HashSeed.fromProcessSeed()` derives each seed through a pseudorandom function keyed by the process seed.** Its input is the calling thread's identity ([07](../07-concurrency/global-state.md#thread-identity)) and a 64-bit count that the thread advances. No two calls give one input, so the seeds they derive are independent, and the count needs no atomic operation, even on a 32-bit target.

**A `HashSeed` isn't `Pod`, and only those two functions make one**, so safe code can't mark a seed it chose as derived from the process seed. Unsafe code that forges that mark only changes what a `Name` feeds its `Hasher` (above). That can't reach compile time, since a `Name` then feeds an address, and turning a pointer into an integer can't run there.

**Each map or set takes a type parameter, `H`, which decides how it seeds the `Hasher`s it feeds its keys to.** `H` defaults to `SeededHashing` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#default-type-arguments)), so `Map<Name, Action>` is `Map<Name, Action, SeededHashing>`:

```swift
struct Map<K: Hashable, V, H: Hashing = SeededHashing> private init(…)
struct Set<T: Hashable, H: Hashing = SeededHashing> private init(…)

protocol Hashing: Copyable {
    @noalloc init()                               // the value a map keeps, unless it is given one
    @noalloc func makeHasher() -> Hasher          // a new hash state, for one key
}
```

A type that conforms to `Hashing` is a **hashing type**. A map or set keeps one value of it, calls that value's `makeHasher()` for each key it hashes, and feeds the key to the result through `hash(into:)` ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)).

**Every `Hasher` that one hashing value or any copy of it makes starts from the same seed**, so a key hashes the same way at every lookup, and a clone's copied table still finds its keys (below). A map whose hashing value breaks this misses keys it holds, but stays memory-safe.

**The primary initializers of `Map` and `Set` are private.** `Map(hashing:)` and `Set(hashing:)` take a hashing value, which the map owns, so a program can give a map one it configured, and every other initializer makes one with `H()`. A map's `clone()` keeps a copy of its hashing value and copies its table as it is, so the clone hashes as the original does.

**A lookup borrows its key, so it takes a `&K`, and a key in a place is lent with nothing written**, an implicitly copyable one too, since the position expects a reference ([05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)). A map or set whose keys are `String`s also looks up a `&Text`, since a `String` hashes and compares as its text does. A string literal is a `static &Text` already, so it passes as it is:

```swift
if let hp = scores[name] { … }            // lends the String 'name' to the lookup
if let hp = scores["grunt"] { … }         // a literal is the '&Text' the lookup takes
if let n = counts[id] { … }               // an Int key is lent too
```

**std provides two hashing types, both implicitly copyable**, since each holds at most a 16-byte seed, and every copy hashes as the first does:

- **`SeededHashing`**, the default, takes a seed of its own from `HashSeed.fromProcessSeed()` when it is made, and starts each `Hasher` from it. So a key's hash, and the order in which a map visits its entries, can differ between maps made separately, and between two runs of one build ([11](../11-compilation-model.md#what-the-language-leaves-open)).
- **`FixedHashing`** holds nothing, so it adds nothing to a map's size. It starts each `Hasher` from a seed that std fixes, so a key's hash depends only on the key. That hash is public: anyone can work out which keys collide, so `FixedHashing` is unsafe for keys that come from outside the program.

A program may declare its own, such as one that holds a secret seed it read at startup, and pass a value of it to `Map(hashing:)`.

**The process seed exists only at run time, so a map or set with `SeededHashing` can't be made at compile time.** The compiler has no run's seed, and keys placed by any other seed would lie where the run's lookups never look. So a map's or set's hashing value decides whether it can be frozen into read-only data:

- **A `const` of one with `SeededHashing` is a compile error**, since a `const`'s initializer must run at compile time.
- **A global `let` of one with `SeededHashing` is built at startup**, since only a value computed at compile time goes into read-only data ([07](../07-concurrency/global-state.md#initialization-at-startup)).
- **One with `FixedHashing` can be frozen**, when what it holds is freezable ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)) and no key's `hash(into:)` feeds an address. So a lookup table such as `bindings` above lies in read-only data, and costs nothing at startup.

**A key that hashes an address keeps its map out of read-only data, whatever the hashing type.** Turning a pointer into an integer can't run at compile time ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)), since freezing and the platform move what it points at. So a map keyed by raw pointers is built at startup. Every hash computed at compile time therefore comes from values that run time sees unchanged, and a `FixedHashing` hash is the same at compile time and in every run of one build.

**A seeded map's order repeats neither from run to run nor between maps made separately, and no setting makes it repeat.** Two maps given copies of one hashing value share one order. So inserting one's entries into the other in that order can cluster them in its table, and slow each insert toward a walk of the whole table, which separate seeds avoid.

**Code that needs one order every run doesn't take it from a seeded map.** A replay, or a test that compares printed output, sorts the keys it visits or uses `FixedHashing`. A lockstep simulation, which compares state across builds and targets, sorts them, since `FixedHashing`'s order depends on std's algorithm.

### Strings

**A value's size is fixed when the program is built, whatever the length of the text it holds or refers to** ([Sizes fixed when the program is built](data-layout.md#sizes-fixed-when-the-program-is-built)). So text whose length has no bound fixed when the program is built lies outside the value, and where it lives follows from where it comes from:

- **Text written in the program**, such as a plain literal's, lies in read-only data, and the literal is a `static &Text` that refers to it, as is any range of one ([02](../02-views-and-dependencies/scoped-values.md#static-values)).
- **Text made at run time lives in storage made at run time.** A `String` owns that storage, so keeping such text takes `alloc` ([06](../06-memory-and-allocators/allocator-basics.md#allocating-with-alloc)), unless the text is interned as a `Name`, whose interner keeps it for the rest of the run ([above](#collections-and-strings)).
- **An interpolated literal is never text by itself**, since its length depends on the values it formats. It is a `Formattable` that writes its pieces into a sink, which needs no storage for the whole text (below), and keeping its text is `alloc "…"` ([below](#literals)). A buffer that bounds the length, such as std's `FixedString`, holds such text without the heap.

**A string is UTF-8 bytes, and formatting writes straight to wherever the text is going:**

```swift
log("hp \(hp)")                                   // written into the log's sink: no allocation
"pos \(p.x), \(p.y)".format(into: mutable buf)    // written into 'buf': no allocation
let title = "Rayo"                                // a static &Text: a reference to the literal's own bytes
let label = alloc "hp \(hp)"                      // formats into a new String: allocates, visibly
let bad: String = "hp \(hp)"                      // error: an interpolated literal is never a String
for g in label.graphemes { … }                    // user-perceived characters, from a sequence of their own
```

**Text comes in two forms: a `String` owns text, and `Text` is a run of UTF-8 that code reaches through a reference.** `Text` is unsized, as `[T]` is, so code holds it as a `&Text`, a pointer and a byte count ([01](../01-values-and-ownership/references.md#unsized-types)). Each kind of text has its own form, and only text that arrives at run time needs a `String`:

- **Fixed text is a literal**, a `static &Text`, which refers to the literal's immortal bytes. It never allocates, can be stored anywhere, and goes wherever a `&Text` is expected ([02](../02-views-and-dependencies/scoped-values.md#static-values)).
- **Formatted output goes straight to its destination**, as `log("hp \(hp)")` formats into the log's sink with no `String` in between (below).
- **Text that is passed around is a `&Text`**, which borrows the text from whatever owns it ([01](../01-values-and-ownership/references.md#references)).
- **A `String` owns text that arrives at run time**, such as a name loaded from a file, a player's input or a message off the network. It allocates, so it is made with `alloc` ([06](../06-memory-and-allocators/allocator-basics.md#allocating-with-alloc)).

**A `&String` converts to a `&Text` of its text wherever one is expected** ([01](../01-values-and-ownership/bindings.md#conversions)), so a function that reads text takes a `&Text`, and its callers give it what they have, which is lent ([05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)):

```swift
func greet(_ who: &Text) { log("hello, \(who)") }

greet(player.name)                        // a String field: lent as a reference to its text
greet("stranger")                         // a literal is a reference to its text already
```

**Owned text says `alloc`**, so every `String` shows where its storage comes from:

```swift
let name = alloc "grunt"                  // owns its text: allocates when it is first written
let wave = level.alloc "Wave \(n) cleared"   // formats into a new String in 'level'
let kept = alloc String(who)              // owns a copy of the text that the '&Text' parameter 'who' names
let plain: String = "grunt"               // error: without 'alloc', a literal is a static &Text
let bare = String("grunt")                // error: making a 'String' needs 'alloc'
```

**`alloc "…"` makes a `String` from a literal** ([below](#literals)), and `alloc String(…)` makes one from text that a literal can't spell out, such as a `&Text` the code was lent.

**A `String` made from a plain literal or a `static &Text` copies its bytes only when it must**, whether by `alloc "…"` or by `alloc String(…)`. The `String` records the allocator `alloc` gives it, as every `String` records its allocator, and is checked against it at each open like any other ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)). But it uses the literal's bytes, which live as long as the program and which nothing writes, until the first call that writes or grows it, which copies them into a buffer from that allocator.

**A bare `String("…")` is a compile error**, as every `Allocating` initializer without `alloc` is ([06](../06-memory-and-allocators/allocator-basics.md#allocating-with-alloc)). Its diagnostic points to the literal itself, which needs no `String`, to `alloc "…"`, and to std's `FixedString`, which the spec leaves to std ([11](../11-compilation-model.md#what-the-spec-defines)).

**Strings are indexed by byte offset.** A range of a `String` or of a `Text`, such as `s[0..<5]`, is a `Text` place with a `borrow` and no `mutate`, so `&s[0..<5]` is a `&Text`, and no code writes bytes that could split a UTF-8 sequence. A range must start and end on Unicode scalar boundaries, or taking it panics, so all text holds whole UTF-8 sequences ([10](../10-errors-and-safety/panics.md#what-panics)).

**A `Text`'s members read it; none changes it**, so a `mutable &Text` lends nothing a `&Text` doesn't. A `String` has them too, beside the members that change it:

| Member | What it is |
| --- | --- |
| `count` | The number of bytes, a read-only `UInt` |
| `s[a..<b]`, and the other ranges | The bytes in the range, a `Text` place with a `borrow`, which panics off a scalar boundary |
| `scalars`, `graphemes` | Sequences of the text's Unicode scalars and of its user-perceived characters |
| `cchars` | The bytes as a `[CChar]` place with a `borrow`, and no NUL after them (below) |
| `==`, `hash(into:)`, `format(into:)` | Comparing, hashing and formatting the text |

**`.cString` is written on a string literal itself, as in `"abc".cString`, and is a `*CChar` to the literal's bytes, which end in a NUL.** So a literal passes to C as a C string at no cost. It is a form of the literal, not a member of `Text`, since a range of static text has no NUL after it. So `title.cString` on a `static &Text` value, or on a `const` imported from a C `#define`, is a compile error. `s.cchars` is any string's bytes as a `[CChar]` place, with a `borrow` and no terminator, for C functions that take a pointer and a length.

**Interpolation writes into a sink.** An interpolated literal, such as `"hp \(hp)"`, evaluates its segments in order, as a call's arguments are evaluated ([01](../01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)). As the message of `fatalError`, `precondition` or `assert`, it is evaluated only when the call panics ([10](../10-errors-and-safety/panics.md#messages)). Its value is a scoped value of a type the compiler builds. That type is `Formattable`: it writes its text and each segment in turn into the sink it is given:

```swift
protocol TextSink { mutating func write(_ text: &Text) where self borrows static }
protocol Formattable { func format(into sink: mutable &some TextSink) where sink borrows static }
```

**A segment takes no mark, and is borrowed where it lies**, since it formats through its plain `format(into:)` method, as a receiver does ([01](../01-values-and-ownership/references.md#unmarked-places)). So `"\(boss.name)"` borrows the name without copying it. Every segment's type must be `Formattable`, as the number types, `Bool`, `String`, `Text` and `Name` are.

**A sink keeps only copies of the text it is given** ([02](../02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in)). So a format may write a reference to its own stack buffer, and a sink takes on no borrow of the temporaries an interpolated literal formats.

**Interpolation itself allocates nothing.** A function that takes a `Formattable`, as `log` does, writes the text where it is going, and `alloc "…"` allocates visibly. Without `alloc`, an interpolated literal has the type the compiler builds for it whatever its context, since no literal protocol takes interpolation. So assigning one to a `String` is an error, and `alloc "hp \(hp)"` builds the `String`.

### Printing

```swift
func print(_ value: &some Formattable)

let hp = 7
let name = alloc "grunt"
print(42)               // 42
print(hp > 0)           // true
print("hp \(hp)")       // hp 7
print(0.1 + 0.2)        // 0.30000000000000004
print(name)             // grunt: a String place, lent, so 'name' stays as it was
```

**`print` writes a value's text, then a newline, to the program's standard output** ([08](../08-c-interop/c-contract-and-embedding.md#what-the-runtime-needs-from-the-platform)). It is a prelude function, and borrows its argument, of any `Formattable` type, since it only reads it ([11](../11-compilation-model.md#the-prelude)). So a place of any type is lent with nothing written, and a value, such as a literal or a call's result, is lent as a temporary ([05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)).

**A reference formats as what it refers to does**, since it takes its `Formattable` conformance from that value ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#conformances)). So `print(x)` and `print("\(x)")` write the same line, whatever `x` holds.

**The language's own types format the same text on every target and in every build**, so a program's printed output can be compared exactly with one recorded on another machine:

- **`Bool`.** `true` or `false`.
- **Integers.** The value in decimal digits, with no leading zeros and a `-` before a negative one: `0`, `42`, `-7`, `18446744073709551615`.
- **Floating-point values.** The text below.

**A `Half`, `Float` or `Double` formats as the shortest decimal that reads back as the same value.** So `0.1` prints `0.1`, though no binary float is exactly one tenth, and every printed float converts back to the bits it came from. Where several decimals of that length read back as the value, it writes the one nearest the value's exact binary value, and of two as near, the one whose last digit is even.

**That decimal is written plainly or with an exponent, depending on its magnitude.** `Float` has an upper bound of 2^24, and `Double` one of 2^53. Up to its bound, each holds every integer exactly, so a whole number keeps all its digits. Past it, a float holds only some of the integers, and writing every digit would claim a precision the value doesn't have:

- **Plain.** A decimal at least `0.0001` in magnitude, of a value no larger than its type's bound in magnitude, is written without an exponent, and always with a fraction: `1.0`, `0.5`, `100.0`, `0.0001`.
- **Exponent.** Any other is written as one digit, then any further digits after a point, then `e`, the exponent's sign and at least two of its digits: `1e-05`, `3.3554432e+07`, `1e+16`.

`Half` takes `Float`'s bound, which is above its largest finite value, 65504, so a whole `Half` always keeps its digits.

**Zeros, infinities and NaN have fixed texts:** `0.0` and `-0.0`, `inf` and `-inf`, and `nan`. Every NaN prints `nan`, whatever its sign or payload, since which NaN a result is stays open ([Floating point](numbers-and-math.md#floating-point)).

```swift
print(Float(16777216))                // 16777216.0: 2^24, the last Float written plainly
print(Float(33554432))                // 3.3554432e+07: past 2^24
print(Double(9007199254740992))       // 9007199254740992.0: 2^53, the last Double written plainly
print(Double(9007199254740994))       // 9.007199254740994e+15: past 2^53
print(0.0001)                         // 0.0001: the smallest magnitude written plainly
print(0.00001)                        // 1e-05
print(-1.0 / 0.0)                     // -inf
print(0.0 / 0.0)                      // nan
```

### Literals

**A literal has no type until something expects one**, so `[1, 2, 3]`, `"jump"` and `0.5` become whatever their context asks for:

```swift
let v: Vec3 = [1, 2, 3]                   // a Vec3: exactly 3 elements
let mask: LayerMask = [.player, .enemies] // a user type that conforms: any number of layers
let jump: Name = "jump"                   // interned by the build: no cost at run time
let lo: Int8 = -128                       // fits: the '-' is checked with the literal
let title: &Text = "Rayo"                 // a static &Text, converted to a plain reference: no allocation
let xs = [3, 4, 5]                        // no context: a [3 of Int], stored inline
let ys: Set<_> = alloc [3, 4, 5]          // a Set<Int>, from the annotation
let zs = alloc [3, 4, 5]                  // a List<Int>: what 'alloc' makes when nothing asks for another type
let msg = alloc "wave \(n)"               // a String: what 'alloc' always makes of a string literal
spawnAll(alloc [.grunt, .brute])          // spawnAll takes a List: the same as spawnAll(alloc List([.grunt, .brute]))
let pair = [boss, copy boss]              // error: an element given a place writes a mark; write 'consume boss' or 'copy boss'
let bad: Vec3 = [1, 2]                    // error: a Vec3 literal needs 3 elements
let ws: List<_> = [3, 4, 5]               // error: a List literal needs 'alloc'
```

**A type takes a literal by conforming to one of the literal protocols**, whose initializer receives the literal:

| Protocol | Requirement | Conforming types |
| --- | --- | --- |
| `ExpressibleByArrayLiteral` | `init<let N: UInt>(arrayLiteral elements: [N of ArrayLiteralElement])` | `Array`, `Simd`, `InlineList`, `List`, `Set`, `std.math`'s `Vec3` and matrices |
| `ExpressibleByDictionaryLiteral` | `init<let N: UInt>(dictionaryLiteral pairs: [N of (Key, Value)])` | `Array` of `(Key, Value)` pairs, `Map`, user types such as a fixed lookup table |
| `ExpressibleByStringLiteral` | `init(stringLiteral text: static &Text)` | `static &Text` |
| `ExpressibleByInternedLiteral` | `unsafe init(internedLiteral entry: static &[InternedEntry])`, and an entry per text ([below](#interned-literals)) | `Name` |
| `ExpressibleByIntegerLiteral` | `init(integerLiteral value: IntegerLiteralType)` | every number type |
| `ExpressibleByFloatLiteral` | `init(floatLiteral value: FloatLiteralType)` | `Half`, `Float`, `Double` |

**A literal becomes the type its position expects, wherever that type conforms**: in an annotation, after `as`, and as an argument, a `return` value or the right side of an assignment. So `spawnAll(alloc [.grunt, .brute])` passes the `List` that the `alloc` builds, as `spawnAll(alloc List([.grunt, .brute]))` would. In an annotation or after `as`, `_` stands for what the literal fills in, as in `Set<_>`. Where a `&Text` is expected, a string literal is a `static &Text`, which converts to it ([02](../02-views-and-dependencies/scoped-values.md#converting-to-and-from-a-static-type)).

**Each element of a literal is a position**, so an element given a place writes its mark, as `pair` above doesn't for `boss` ([01](../01-values-and-ownership/references.md#places-given-to-a-position)). An element whose expected type is a `&T` takes a bare place, which it lends, as an element of a `[&Enemy]` does.

**A literal never allocates by itself.** An array or dictionary literal becomes a type that conforms to `Allocating`, such as a `List`, `Set` or `Map`, only under `alloc`, which passes its initializer the allocator, as it does any `Allocating` initializer's ([06](../06-memory-and-allocators/allocator-basics.md#allocating-with-alloc)). So `[3, 4, 5]` with no context is an inline array, and `alloc [3, 4, 5]` with no context is a `List`. A dictionary literal under `alloc` with no type expected is a compile error, so the code writes the type, as in `let ids: Map<Name, Int> = alloc ["jump": 0]`. An array or dictionary literal that would become an `Allocating` type without `alloc`, such as `ws` above, is a compile error.

**A string literal under `alloc` always makes a `String`**, from the allocator `alloc` takes, as an array literal under `alloc` makes a `List`. Unlike an array literal, it does so whatever its position expects, so `msg` above is a `String`. An interpolated one formats its text into the new `String`. Without `alloc`, an interpolated literal is never a `String`, and a plain literal is a `static &Text` ([above](#strings)). So a type that conforms to `Allocating` can't conform to `ExpressibleByStringLiteral`: a literal of it would need `alloc`, which makes a `String` instead.

**In `@noalloc` code, a literal converts only where that can't allocate** ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)). That holds when either of these does:

- its initializer is `@noalloc`, as those of the number types, `Array`, `Simd`, `InlineList`, `static &Text` and `std.math`'s `Vec3` and matrices are;
- its literals convert at compile time (below), as `Name`'s do.

So a `List`, `Set` or `Map` literal is an error there, as its `alloc` is.

**An array literal's elements arrive inline**, as an `[N of Element]` that the initializer owns, whose count is known at compile time, never as a heap buffer. So a type refuses a count it can't hold at compile time, through `static if` and `static error` ([09](../09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation)): `Simd<T, N>` takes exactly `N` elements, `Vec3` exactly 3 and `InlineList<T, 8>` at most 8. Passed where an `[N of T]` with an unbound `N` or `T` is expected, as for `alloc List([1, 2, 3])`, a literal binds `N` to its count and `T` as it does with no context.

**An integer or float literal is checked against the type it becomes.** An integer literal must fit the conformer's `IntegerLiteralType`, at compile time. A float literal is rounded once, to its `FloatLiteralType`, which is `Half`, `Float` or `Double`. A prefix `-` applied to a literal, directly or through parentheses, where an operand begins, makes one literal of the opposite sign, checked as one value. So `-128` fits an `Int8`, although `128` alone doesn't, while `n-1` still subtracts. Likewise `-(1)` is the literal `-1`, which fits no unsigned type, and `-(-(1))` is the literal `1`. A postfix member applies to the literal first, so `-128.abs` is `-(128.abs)`.

**With no context, a literal has a default type:**

- an integer literal is an `Int`, and a floating-point literal a `Double`;
- a string literal is a `static &Text`;
- a dictionary literal is an `[N of (K, V)]`;
- an array literal is an `[N of T]`, whose `T` is the type of its typed elements, which must agree.

**When every element is a literal, the elements take one default together:**

- for number literals, `Double` if any is a floating-point one, and `Int` if none is;
- for literals of one other kind, that kind's default, so `["a", "b"]` is a `[2 of static &Text]`.

Literals of different kinds, such as `1` and `"a"`, are an error. An empty `[]` or `[:]` needs a context.

**A literal of constants converts at compile time.** A literal of constants is one whose elements, at any depth, are literals or `const`s. It converts when its initializer can run at compile time ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)) and the value it builds owns nothing outside its own bytes:

- no allocation;
- no object;
- no `Synchronized` value;
- no `Allocator` id but `.heap`;
- no pointer but one into immortal data, as a literal's `static &Text` or a `Name` holds.

`Name`, `Simd`, an `[N of T]` or `InlineList` of such values, and `std.math`'s `Vec3` and matrices qualify. Each evaluation takes a new copy of the bytes, as a `const` of a copyable type is taken ([01](../01-values-and-ownership/moving-values-out.md#constants)). So a `Name` literal costs nothing at run time. A matrix holds an inline array of its columns, so it is never implicitly copyable, and a copy of one is written ([01](../01-values-and-ownership/moves-copies-destruction.md#implicitly-copyable-types)).

**Any other literal runs its initializer on each evaluation**, as a `List`'s allocates from the allocator its `alloc` gives. Whether or not a literal converts, when its initializer can run at compile time, a precondition it breaks on constant elements is a compile error.

**A `Map` or `Set` literal with two equal keys breaks its initializer's precondition, so it panics at run time** ([10](../10-errors-and-safety/panics.md#assert-and-precondition)). Keys that are constants are checked before then, whatever the hashing type: the compiler compares them with `==` at compile time, wherever their `==` can run there, without building the map. So two equal constant keys are a compile error even in a literal of a `SeededHashing` map, whose initializer runs only at run time ([Hash maps and sets](#hash-maps-and-sets)).

**`true` and `false` are only `Bool`, and `nil` only an optional.**

#### Interned literals

**A type interns its string literals with the build's help by conforming to `ExpressibleByInternedLiteral`**, as std's `Name` does. The build makes each text's entry once, and the type's interner starts out holding them all. So a literal costs nothing at run time, and still names the entry that interning its text at run time finds:

```swift
protocol ExpressibleByInternedLiteral where InternedEntry: ~Scoped {        // an entry refers to nothing that ends
    associatedtype InternedEntry: Frozen & TrivialFree & Sendable         // one per distinct text
    static func internedEntry(for text: static &Text) -> InternedEntry     // run by the compiler, once per distinct text
    @noalloc unsafe init(internedLiteral entry: static &[InternedEntry])   // the entry the build bound for the literal
    unsafe static func internLoaded(_ entries: static &[InternedEntry],    // code loaded after startup (below)
                                    binding bound: mutable &[static &[InternedEntry]]) -> Void!AllocError
}
```

- **One table per type.** The table holds an entry for each text the build converts to a `T` literal in checked code, anywhere in the program. The build runs `internedEntry(for:)` once per text and freezes the results into one table in read-only data, so equal texts in different modules share one entry.
- **Entries are freezable.** `InternedEntry` is `Frozen`, `TrivialFree`, `Sendable` and unscoped, and the build checks the rest of the freezable test on each entry it makes ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).
- **A stray entry never becomes a value.** `internedEntry(for:)` is safe to call from anywhere, since it only builds an entry from a text and touches no interner. An entry built that way never becomes a value of the type, since only `unsafe` code calls `init(internedLiteral:)`, promising the entry is the one the build bound (below). std's `Name` also keeps its entry's fields private.
- **The table exists only at run time.** `T.internedLiterals`, a `static &[T.InternedEntry]`, refers to it. Compile-time code can't read it, and `static if` can't test it, since what it holds depends on every literal the build checks, compile-time code's included.
- **Each literal is built at compile time.** The `@noalloc` `init(internedLiteral:)` receives the literal's element of the table, and must be able to run at compile time, so every such literal converts at compile time ([above](#literals)).
- **Its caller promises the entry.** `init(internedLiteral:)` is `unsafe`: its caller promises that the reference is to the entry the build bound for that literal, since an entry from anywhere else would give its text a second value. The call the build makes for a literal carries that promise itself, so a literal needs no `unsafe` in source, in a `@safe` module too ([10](../10-errors-and-safety/unsafe-code.md#what-needs-unsafe)).
- **The table seeds the interner.** std's `Name` interner reads `Name.internedLiterals` in its own global's initializer. Interning reads that global, so the initialization checks keep any code from interning before the table is in it ([07](../07-concurrency/global-state.md#initialization-at-startup)).

**A conformer is a type that can declare a static stored `let`, and doesn't also conform to `ExpressibleByStringLiteral`.** It keeps its interner in a static stored `let`. So it is none of the places 07 lists where one declaration stands for many instances, such as a generic type, a type nested in one or a type local to a generic function ([07](../07-concurrency/global-state.md#global-state)). A type that conforms to both protocols is a compile error, since a string literal of it would have two meanings.

**Code loaded after startup binds its literals to entries before it runs.** The spec defines no way to load code after startup ([11](../11-compilation-model.md#what-the-spec-defines)). It fixes only what a layer that does so, such as a hot reloader, builds on:

- **Each literal reaches its entry through a symbol** keyed by the type and the text, and so does each frozen value that holds one. In the program the build links, the symbol names the text's element of the table, and a loader may bind it to an existing entry instead.
- **`internLoaded(_:binding:)` takes the new code's entries before that code runs.** The conformer interns each one, and stores in `bound[i]` the entry that `entries[i]`'s text binds to: `entries[i]` itself for a new text, or the entry the text already has. The loader binds each symbol to that entry, so equal texts still give one `Name`.
- **It is `unsafe`**, since its contract assumes what only the loader knows: that `entries` is the new code's table, and that the loader binds each symbol through `bound` as placed ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)).
- **It fails with `AllocError` when the interner can't grow**, so the loader can refuse the code. std's `Name` implements it with its interner.
- **Loaded code shares the program's function for an entry's hash.** Its entries carry hashes its own build computed, so it must come from a build whose function for an entry's hash is the running program's. A loader that can't confirm this refuses the code.
- **Loaded code shares std's hashing code with the program**: `Hasher`, `FixedHashing`'s seed, how `HashSeed` derives seeds, and std's `hash(into:)` implementations. It may look up a map that the program built or froze, which only the same code finds its keys in ([Hash maps and sets](#hash-maps-and-sets)). A loader that can't confirm this refuses the code.

### Iteration

**A `for` loop's subject says what the loop does with the elements: reads them where they lie, changes them there, or takes them:**

```swift
var total: Float = 0
for e in &enemies { total += e.hp }                        // 'e' is a 'ref let' of each element
for e in mutable enemies { e.hp -= 1 }                     // 'e' is a 'ref var' of each element
for job in consume jobs { run(consume job) }               // takes the list: 'job' owns each job
for (i, e) in items.mutableEnumerated() { e.order = i }    // 'i' is a UInt, and 'e' a 'mutable &Item'
for (v, f) in vels.mutableZip(forces) { v += f * dt }      // two sequences in lockstep
```

**A subject writes its mark, or is a value, and what each name is follows from it** ([01](../01-values-and-ownership/bindings.md#for-and-when-names)). So iterating a place never copies it: `&s` and `mutable s` lend it to the loop, and `consume s` moves it in.

```swift
protocol Sequence { associatedtype Iterator: IteratorProtocol; func makeIterator() -> Iterator }
protocol IteratorProtocol { associatedtype Element; mutating func next() -> Element? }   // may lend
protocol SharedIterator: IteratorProtocol {     // elements outlive the iteration (02)
    mutating func next() -> Element? where return outlives self
}
protocol Collection: Sequence where Iterator: SharedIterator { var count: UInt { get } }   // what generic algorithms take

protocol MutableSequence {                      // what 'for x in mutable s' iterates
    associatedtype MutableIterator: IteratorProtocol   // a collection's hands out mutable references; a Receiver's, owned items
    mutating func makeMutableIterator() -> MutableIterator
}

protocol ConsumingSequence {                    // what a loop over a whole value takes
    associatedtype ConsumingIterator: IteratorProtocol
    consuming func makeConsumingIterator() -> ConsumingIterator
}
```

**A collection's shared and mutable iterators hand out references to its elements, and its consuming iterator hands out the elements themselves:**

- its iterator hands out a `&T` of each element, one pointer;
- its mutable iterator hands out a `mutable &T` of each element;
- its consuming iterator hands out each `T` itself.

A reference reaches an element without moving it, so move-only elements iterate like any others.

**A loop runs as a `while` over an iterator that its subject picks**, where `S` is what the subject refers to or holds:

| Subject | Iterator | Each pass |
| --- | --- | --- |
| A shared reference: `&s`, or a value of type `&S` | `var it = S.makeIterator()`, through the reference | `while let b = it.next()`: bind the pattern to `b′`, then run the body |
| A mutable reference: `mutable s`, or a value of type `mutable &S` | `var it = S.makeMutableIterator()`, through the reference | `while var r = it.next()`: bind the pattern to `r′`, then run the body |
| Any other value whose type conforms to `ConsumingSequence`, such as `consume s` | `var it = S.makeConsumingIterator()` | `while let b = it.next()`: bind the pattern to `b′`, then run the body |
| Any other value | `var it = S.makeIterator()` | `while let b = it.next()`: bind the pattern to `b′`, then run the body |

- **A loop over `&s` holds `s` borrowed shared, and one over `mutable s` holds it exclusively, until the loop ends.** The mark picks the form, as it picks the reference an argument passes ([01](../01-values-and-ownership/references.md#making-a-reference)). So a loop that changes elements in place writes `mutable`.
- **`mutable` on a subject needs a changeable place, as it does anywhere** ([01](../01-values-and-ownership/bindings.md#changeable-places)). A temporary isn't one, so `mutable makeEnemies()` is a compile error, while `for e in makeEnemies()` owns each element and may change it. A place property with a `borrow` and no `mutate` can't be lent this way.
- **A subject lent from a place property changes the storage its place lies in**, as `mutable hits.span` changes the elements of `hits`.
- **A loop over a whole value whose type conforms to `ConsumingSequence`** gives it to the iterator. So a loop over `consume jobs` hands each job over, and the iterator's `deinit` destroys the elements a `break`, `return` or `throw` leaves. `[N of T]` conforms to `ConsumingSequence`, as std's owning collections do.
- **Through a reference subject, an element that is itself a reference is bound in place.** A name bound to the whole of `b` is a `ref let` of what `b` refers to, as `ref let x = b` would be. One bound to `r` is a `ref var`, as `ref var x = mutable r` reborrows through it ([01](../01-values-and-ownership/bindings.md#bindings-that-refer-to-a-place)).
- **Any other element is a value the iterator hands out**, such as a range's `Int`, a chunk or an `enumerated()` tuple. Then `b′` is `consume b` and `r′` is `consume r`, and the name owns it for the iteration, as `i` does below.

```swift
for i in 0..<n { ids.append(i) }           // 'i' owns each Int for its iteration
for (i, e) in items.enumerated() { … }     // the loop owns each tuple: 'i' a UInt, and 'e' a '&Item'
for e in &enemies where e.hp > 0 { … }     // the body runs only where the condition holds
for t in visibleTiles() { … }              // 'visibleTiles()' returns a '&[Tile]': 't' is a 'ref let' of each tile
```

**A value subject is moved into a hidden local that lives until the loop ends**, and so is every temporary in the subject's expression, each into its own, in evaluation order. Each is still a temporary, so it stays read-only ([01](../01-values-and-ownership/bindings.md#changeable-places)). An adaptor in a hidden local keeps its collection borrowed for the whole loop:

```swift
for (i, e) in makeEnemies().enumerated() { … }          // the new list is a hidden local, and so is its adaptor
```

**What each name of the pattern binds decides whether it can change** ([01](../01-values-and-ownership/bindings.md#for-and-when-names)):

- **A name bound in place is a `ref let` through `&`, and a `ref var` through `mutable`.** So a loop that changes its elements writes `mutable` on the subject, or iterates a sequence that hands out mutable references, such as `mutableEnumerated()`. It writes nothing on the pattern, as a loop that reads them writes nothing there either.
- **A value the iterator hands out is owned by its name**, such as a range's `Int`, a handle or a chunk. The name may change what it owns, as a chunk is written through, but is never assigned as a whole.

**A `where c` after the sequence runs the body as `if c { body }`**, with the pattern bound, as in the `enemies` loop above.

**`while` takes conditions as `if` does** ([01](../01-values-and-ownership/bindings.md#conditions)), and narrows as `if` does ([Narrowing](enums.md#narrowing)). `repeat { … } while c` tests `c` after each pass. A label, as in `outer: for row in &grid`, lets a nested loop's `break outer` or `continue outer` name that loop.

**Which elements outlive the iteration follows from the dependency rules** ([02](../02-views-and-dependencies.md#dependencies)):

```swift
func scale(_ s: mutable &[Float]) { for x in mutable s { x *= 2 } }
var names = alloc List<&Text>()
for s in &table.entries { names.append(s.name) }                // fine: each element depends on 'table', not the iterator
for chunk in data.mutableChunks(64) { scale(mutable chunk) }    // one 'mutable &[Float]' at a time: 'chunk' owns it, and lends 'scale' a reborrow
```

**An iterator that hands out mutable references lends.** Its `mutating` `next()` makes each element depend exclusively on the iterator until the next call, so two are never live at once. Keeping a chunk past its iteration, or holding two, is a compile error. `mutableSplit(at:)` gives two at once ([Runs of elements](#runs-of-elements)).

**`zip` is a method of every collection.** `a.zip(b)` reads both, and `a.mutableZip(b)` changes the receiver's elements and reads the argument's. Each hands out tuples, and stops at the shorter, so every element is in bounds. Three or more nest: `a.zip(b).zip(c)` hands out `((x, y), z)`, and `a.mutableZip(b.zip(c))` changes `a`'s elements beside the other two's.

**A `mutableZip` is a move-only value whose only iteration is the consuming one.** So a loop over a place holding one consumes it explicitly, and no two iterators hand out its mutable references:

```swift
for (x, y) in consume z { … }       // 'z' holds a mutableZip: its only iteration consumes it
```

### Shared and mutable views of one collection

**A place property or subscript with a `borrow` and a `mutate` serves both kinds of reference under one name** ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate)). `&x.p` and a read through `x.p` use the `borrow`. `mutable x.p`, a write through `x.p` and a `mutating` call on it use the `mutate`. So a collection's elements, a range of them and an `SoA`'s column each have one name:

```swift
var span: [T] { borrow { … } mutate { … } }                     // a list's elements, as a place
subscript(r: Range<UInt>) -> [T] { borrow { … } mutate { … } }  // a range of them
```

```swift
let all = &hits.span                      // a '&[Int]', through the borrow
var some = mutable hits[0..<4]            // a 'mutable &[Int]', through the mutate
particles.life.sort()                     // a mutating method, through the column's mutate: sorts it in place
func lives(_ p: mutable &SoA<Particle>) -> mutable &[Float] { mutable p.life }    // a result of one
```

**`mutable` of a member with only a `borrow` is a compile error**, since nothing lends that place for change ([01](../01-values-and-ownership/references.md#making-a-reference)). So a member whose place must never change through it, such as a range of a `String`, declares only a `borrow` ([Strings](#strings)).

**A method with a shared and a mutable form has two names**, since a call's result is a value, and a mark before the call would lend that value rather than pick a form. The mutable form is a `mutating` method whose name puts `mutable` before the shared one's:

| Shared | Mutable |
| --- | --- |
| `data.chunks(64)` | `data.mutableChunks(64)` |
| `items.enumerated()` | `items.mutableEnumerated()` |
| `vels.zip(forces)` | `vels.mutableZip(forces)` |
| `s.split(at: m)` | `s.mutableSplit(at: m)` |
| `bytes.reinterpret(as: U.self)` | `bytes.mutableReinterpret(as: U.self)` |

A run's members table says what each of these hands out ([Runs of elements](#runs-of-elements)).

**No receiver takes a mark, so the mutable form's receiver takes none, and it must be a changeable place** ([01](../01-values-and-ownership/bindings.md#changeable-places)). What it returns depends on the receiver exclusively, by rule 3 ([02](../02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)). A binding that writes through a mutable reference it holds is a `var`, since writing through a reference needs a changeable place ([01](../01-values-and-ownership/references.md#forwarding-through-a-reference)):

```swift
for (i, e) in items.enumerated() { … }               // (UInt, &Item) elements
for (i, e) in items.mutableEnumerated() { … }        // (UInt, mutable &Item) elements
var (lo, hi) = samples.span.mutableSplit(at: 64)     // two 'mutable &[Float]'s: 'samples' stays borrowed exclusively
lo[0] = 0
```

### Mutating and consuming methods

**A `consuming` method that hands over what a `mutating` one lends puts `consuming` in its name**, as `makeConsumingIterator()` does. Each name has one declaration, so the name a call writes says whether it lends or hands over ([05](../05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures)). A place property with a `borrow` and a `mutate` is one declaration, which serves both kinds of reference ([above](#shared-and-mutable-views-of-one-collection)):

```swift
var (a, b) = s.mutableSplit(at: m)       // lends two halves of what 's' refers to
var (c, d) = s.consumingSplit(at: m)     // takes 's', and hands the halves over
```

**Here `s` holds a `mutable &[T]`.** `s.mutableSplit(at: m)` is a member of the run, reached through `s`, so it lends two halves that depend on `s` exclusively, and needs `s` changeable. `s.consumingSplit(at: m)` is the one member that a mutable reference to a run has of its own ([01](../01-values-and-ownership/references.md#forwarding-through-a-reference)). It takes `s` and hands the halves over, carrying only what `s` carried, by rule 3 ([02](../02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)).

**A shared reference needs no consuming split.** Reaching through a `&[T]` carries what it carries and leaves the place that holds it unborrowed, as a reborrow through it does ([01](../01-values-and-ownership/references.md#reborrowing)). So the halves of `split(at:)` already outlive that place.
