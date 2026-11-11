# Constants and conditional compilation

[09 · Compile time](../09-compile-time.md)

## Running code at compile time: `const`

A table worked out ahead of time, such as a sine table, a name interned once or a list of presets, is a `const`, and the function that builds it is ordinary code that the compiler runs:

```swift
const maxPlayers = 8
const sinTable: [1024 of Float] = makeSinTable()        // runs in the compiler
const jumpId: Name = "jump"                             // interned by the build

func makeSinTable() -> [1024 of Float] {
    var t: [1024 of Float] = .init(repeating: 0)
    for i in 0..<1024 { t[i] = sin(Float(i) / 1024 * 2 * .pi) }
    return t
}
```

**A `const` initializer is evaluated at compile time.** It is checked as the body of a function with no parameters that returns the `const`'s type, as a default value is ([01](../01-values-and-ownership/parameters.md#default-arguments)). So, as for a default, a view it returns views only static storage ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)).

**Any function can run at compile time if what it executes, on the input it gets:**

- calls no C function, whether imported or declared `extern c`;
- accesses no global other than a `const`, a `static const` included, and no thread-local;
- starts, parks and wakes no thread: it reaches no blocking wait, `Runtime.park` or `Runtime.wake`;
- makes no volatile access, and no access through a pointer made from an integer;
- turns no pointer into an integer, since freezing moves what a pointer points at and the platform places the program anew in each run, so the integer would differ at run time;
- reads no clock;
- reads no random value from the platform, such as the process seed, which a `Map` or `Set` with the default `SeededHashing` reads when it is made ([04](../04-types/collections.md#hash-maps-and-sets)).

**A `const` whose initializer does anything else is a compile error**, while a global `let`'s runs at startup instead ([07](../07-concurrency/global-state.md#initialization-at-startup)).

**Allocator code that aligns with the pointer queries that expose no address, not `CUIntPtr(bitPattern:)`, runs at compile time** ([10](../10-errors-and-safety/unsafe-code.md#raw-pointers)).

**Evaluation runs ordinary code, under these rules:**

- **What runs is what counts.** A function with a branch that reads a global `let` still runs in the compiler on an input that never takes that branch.
- **It computes what run time would.** Each scope keeps the diagnostic checks it has at run time, as `target.checks` reports them ([10](../10-errors-and-safety/checks-and-build-modes.md#check-levels)). So an overflow wraps where overflow checks are off. A panic is a compile error that reports it.
- **`unsafe` and `unchecked` code run too, checked.** Every raw access is checked against what an access through a raw pointer must satisfy ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)), and every memory-safety check an `unchecked` block removes still runs. So an access outside its allocation, into freed memory, misaligned or of an invalid value is a compile error. `unsafe` code that breaks a promise evaluation can't check, such as respecting a live borrow, gets no promise about the `const`'s value, as it gets none at run time. A diagnostic check that an `unchecked` block removes stays off, as at run time ([10](../10-errors-and-safety/checks-and-build-modes.md#unchecked-blocks)).
- **Allocation works.** At compile time `.heap` allocates from a compile-time heap, so `alloc`, containers, strings and allocators run as they do at run time, and `makePresets()` below can build a `List` with `append`. Running out of it exceeds the toolchain's limit (below), never an allocation failure that code observes, so no value depends on the building machine's memory.
- **One thread.** Evaluation runs on one thread, so no `const`'s value depends on thread timing.
- **Evaluation is bounded.** A `const`'s evaluation that runs past the toolchain's limit is a compile error, so a runaway loop fails the build instead of hanging it. A global `let`'s leaves the global to startup, which computes the same value ([07](../07-concurrency/global-state.md#initialization-at-startup)).
- **No cycles.** A `const` whose evaluation reads itself, directly or through other `const`s, is a compile error.

### Consts that reach run time

A `const` can allocate while the compiler builds it, but the running program has no compile-time heap. So a `const` that reaches run time is copied into the program's read-only data.

A `const` **reaches run time** when code names it anywhere but in these places, whether or not the code that names it ever runs:

- a `const` initializer;
- the condition or list of a `static if` or `static for`;
- an attribute argument;
- a `const` argument, such as a shuffle's index list ([04](../04-types/numbers-and-math.md#shuffles-and-swizzles)).

Here `enemyPresets` reaches run time, since `presets()` names it, even if nothing calls `presets()`:

```swift
struct Preset(var name: String, var hp: Float) {
    alloc func clone() -> Preset { Preset(name: alloc name.clone(), hp: copy hp) }   // so a List<Preset> can be cloned
}

const enemyPresets: List<Preset> = alloc makePresets()   // built in the compiler, allocating as it goes

alloc func makePresets() -> List<Preset> {
    var a = alloc List<Preset>()
    a.append(Preset(name: alloc "grunt", hp: 50))
    a.append(Preset(name: alloc "brute", hp: 400))
    return a
}

func presets() -> Span<Preset> { enemyPresets.span }   // a static view, converted to the plain one: any function may return it

struct World(var presets: static Span<Preset>, …)

func setUp(_ world: mutable World) {
    world.presets = enemyPresets.span                  // a static view by itself, so a field can keep it
    var edited = alloc enemyPresets.clone()            // fine: a run-time copy, from the ambient allocator
    edited.append(Preset(name: alloc "boss", hp: 900))
    enemyPresets.append(Preset(name: alloc "boss", hp: 900))   // error: a const is never mutated
}
```

**A `const` that reaches run time is frozen into read-only data.** It keeps its declared type, and its buffers carry the static allocator, as a global `let`'s in read-only data do ([07](../07-concurrency/global-state.md#initialization-at-startup)). The static allocator never allocates or frees at run time ([06](../06-memory-and-allocators/allocator-basics.md#the-static-allocator)).

**Freezing copies the value out of the compile-time heap, which the running program lacks.** It does three things:

- **Allocations.** It copies each compile-time heap allocation that the value reaches through a raw pointer, a container's included, once, as one allocation ([10](../10-errors-and-safety/unsafe-code.md#allocations)). The copy is in read-only data, aligned at least as the allocation was.
- **Pointers.** It points each pointer into a copied allocation at the same offset in its copy. Evaluation never turns a pointer into an integer (above), so no integer in the value is an address that freezing would leave stale.
- **Allocator words.** It makes every allocator word in the value the static allocator's, whether or not it records an allocation: an empty `List`'s and a literal-backed `String`'s record none.

**A frozen `const` lives as long as the program** ([01](../01-values-and-ownership/moving-values-out.md#constants)), so its views are static views. For a `List` or an `[N of T]` reached from a `const` through stored fields and place properties, `.span` is a `static Span<T>`. For a `String` reached that way, as `enemyPresets[i].name` is, `.view` is a `static StringView`. Either may be kept anywhere, since what it views is never freed ([Static views: views of immortal data](attributes-and-runtime-data.md#static-views-views-of-immortal-data)), and converts to the plain view wherever one is expected ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)).

**What can be frozen.** A `const` that reaches run time must be **freezable**, or it is a compile error. A frozen value lies in read-only data, where nothing consumes, mutates or destroys it ([06](../06-memory-and-allocators/allocator-basics.md#the-static-allocator)), and every thread may read it. It is built at compile time and read at run time, so it reaches nothing that exists only at run time, and nothing from compile time but what freezing copies. So a freezable value meets each of these:

- **Nothing writes it.** It is `Frozen`: nothing writes what it holds or owns through a shared borrow ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)), and nothing ever mutates a value in read-only data. A type declared `: unsafe Frozen` promises that nothing writes a frozen value of it, bookkeeping included. So a freezable value holds no `Synchronized` value, and a global `let` of a `Synchronized` type is initialized at startup, in memory its methods can write ([07](../07-concurrency/global-state.md#initialization-at-startup)).
- **Destroying it would only free memory.** It is `TrivialFree` ([06](../06-memory-and-allocators/allocation-lifecycle.md#releasing-a-value-without-destroying-it-trivialfree)). A frozen value is never destroyed, which skips only frees, and those free nothing under the static allocator. So a `Shared` or a `LocalShared` isn't freezable, although it may be `Frozen`: its count is written at run time, and its `deinit` isn't `PlainDeinit`.
- **No pin counts.** It holds no `StablePool`, whose pin counts are written at run time, as `Shared`'s count is ([03](../03-handles-and-objects.md#pinning-for-c)).
- **No weak pointers or weak links.** It holds none at any depth, since the objects and `Shared` values they name exist only at run time ([03](../03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert), [06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)). So a `Slice` or a `Waker`, which holds a weak link, isn't freezable either.
- **No allocator ids but `.heap`.** It holds no `Allocator` id but `.heap`, since an allocator registered at compile time doesn't exist at run time. So a global `let` that registers one, such as `frameArena` below, is initialized at startup.
- **No stale values.** It holds no stale owning value: every owning value in it would pass an open when evaluation ends ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).
- **Pointers only into memory that lasts.** Through its raw pointers it reaches only live compile-time heap memory, which freezing copies (above), or immortal data: a literal's bytes, the data behind any static view, another `const`'s frozen data, type metadata and code. It reaches no freed memory. A pointer made from an integer, such as a device register's, is frozen as it is, since evaluation never got that integer from a pointer (above).
- **Unscoped.** It is unscoped ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)), unless every view it holds depends on nothing, as a function value made from a named function does ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)). Freezing follows only raw pointers, so any other view would still point at compile-time memory. A frozen value views frozen data through a static view (above).
- **Readable from any thread.** It has a `Sendable` type, as every global that safe code reaches does ([07](../07-concurrency/global-state.md#global-state)).

**Which maps and sets can be frozen follows from these rules**: a value whose layout comes from the process seed or from an address is never built at compile time ([04](../04-types/collections.md#hash-maps-and-sets)).

**The same test, with the rules above for what can run at compile time, decides which global `let`s go into read-only data** ([07](../07-concurrency/global-state.md#initialization-at-startup)). So the first three below are initialized at startup, and only the last is frozen:

```swift
let frameArena = Allocator.register(Arena(size: 64.mb))                      // holds an allocator id other than .heap
let godMode = Atomic(false)                                                  // Synchronized: kept in memory its methods can write
let presetIds: Map<Name, Int> = alloc ["grunt": 0, "brute": 1]               // seeded hashing: can't run at compile time
let fixedIds: Map<Name, Int, FixedHashing> = alloc ["grunt": 0, "brute": 1]  // fixed hashing: frozen into read-only data
```

**A `const` that doesn't reach run time, such as a list iterated by `static for`, may hold anything.** An attribute made from one must still be freezable ([Attributes](attributes-and-runtime-data.md#attributes)).

## `static if` and conditional compilation

`static if` keeps or drops code at compile time, by the target platform, a build flag or what a type argument supports:

```swift
static if target.platform == .ps5 || target.platform == .xboxSeries {
    typealias GpuResourceId = UInt64
} else {
    typealias GpuResourceId = UInt32
}

static if !target.flag("sse4") {
    static error("needs SSE4")                                  // fails the build where the flag is off
}

func store<T>(_ value: T, into w: mutable Writer) {
    static if T.conforms(Pod.self) && T.isPaddingFree {
        w.bytes(of: value)                                      // fast path for plain data: safe, one memcpy
    } else {
        serialize(value, into: &w)
    }
}
```

**The branch a `static if` doesn't take is parsed but not type-checked**, so it can mention symbols that only exist on another platform. Conditions must be `const`.

**At the top level, `static if` can include or exclude declarations and whole `import` and `import c` statements.** A condition that guards an import reads only these, so which modules a file imports never depends on what an import provides or on the module's own declarations:

- literals;
- `const`s of modules imported outside any `static if`;
- the prelude's `target`, never a declaration of the module's own that shadows it ([11](../11-compilation-model.md#the-prelude)).

No `import` goes inside a `static for`, at any depth.

**In generic code, a branch is checked only for the instantiations whose condition holds** ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)). That lets `store` call `w.bytes(of:)`, which accepts only a padding-free `Pod` type ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). `T.isPaddingFree` is a reflection query ([What reflection can read](reflection.md#what-reflection-can-read)).

**`static error("…")` refuses an instantiation or a build.** It turns a branch that must not be instantiated or built into a compile error with that message, as the complete serializer does ([Static reflection](reflection.md#static-reflection)). It stands where a statement, a member, a field or a top-level declaration can, as the `sse4` check above does at the top level.

**`target` is a `const` the prelude declares, which describes the build** ([11](../11-compilation-model.md#the-prelude)). It exposes:

- `platform`, `arch` and `endian`;
- `pointerBitWidth`, the target's pointer width, an `Int` of 32 or 64 ([11](../11-compilation-model.md#what-a-target-must-provide));
- `has64BitAtomics`, a `Bool` that says whether the target has lock-free 8-byte atomics, without which an 8-byte `Atomic` is a compile error ([07](../07-concurrency/synchronization.md#atomics-and-locks));
- `mode`, the build mode: `.debug` or `.release` ([10](../10-errors-and-safety/checks-and-build-modes.md#build-modes));
- `checks`: the set of diagnostic checks that are on where it is read, as `@checks` names them ([10](../10-errors-and-safety/checks-and-build-modes.md#check-levels));
- `cStackReserve`: the stack, in bytes, that a call into C checks is left, unless the C function called declares its own need with `stack(n)` ([08](../08-c-interop/imports-and-inline-c.md#the-stack-a-c-call-needs));
- flags the build defines: `target.flag("editor")`, or `target.flag("poolSize")` for one holding a number, with the type and value the build gives it ([What a build declares](attributes-and-runtime-data.md#what-a-build-declares)).

**Reading a flag the build doesn't declare is a compile error.** `target.hasFlag("editor")`, a `const` `Bool`, says whether the build declares that flag. So a library can read a flag that only some builds define inside a `static if` on `hasFlag`:

```swift
static if target.hasFlag("editor") {          // whether this build declares 'editor'
    static if target.flag("editor") { … }     // so the flag is read only in builds that declare it
}
```
