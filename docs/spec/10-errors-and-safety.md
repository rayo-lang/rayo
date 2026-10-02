# 10 · Errors and safety

A **recoverable error**, such as a missing file, is a typed value that the caller must handle. A **bug**, such as dereferencing a stale handle, **panics** ([below](#panics)).

```swift
enum ConfigError: Error {
    case notFound
    case badValue(field: StaticString)
}

func loadConfig(_ path: StringView) throws(ConfigError) -> Config { ... }   // the signature names the error type

do {
    settings = try loadConfig(path)       // a missing file is expected: it comes back as a value
} catch .notFound {
    settings = Config()                   // fall back to the defaults
} catch .badValue(let field) {
    log("bad value for \(field)")
}

let pos = enemies[target]!.pos            // a stale handle here is a bug: '!' panics
```

## Typed `throws`

A function that can fail in an expected way reports the failure to its caller as a value, and its signature says which errors it can throw:

```swift
enum LoadError: Error {
    case notFound(path: StaticString)
    case corrupt(offset: Int)
    case unknownCase(Name)                  // reflective loaders (09)
    case badValue(field: StaticString)
    case outOfMemory
}

func loadMesh(_ path: StringView) throws(LoadError) -> Mesh {
    let bytes = try readFile(path)                      // readFile throws(IoError); converted below
    guard bytes.count >= MeshHeader.size else { throw .corrupt(offset: 0) }
    ...
}

extension LoadError {                                   // enables 'try' across error types
    @converts init(_ e: owned IoError) { self = if e == .missing { .notFound(path: "?") } else { .corrupt(offset: -1) } }
    @converts init(_ e: owned ParseError) { self = .corrupt(offset: e.offset) }
}
```

**A public function's `throws` names its error type, and throwing costs the same as returning:** a throwing function returns its result or its error as a tagged union, with no unwinding and no allocation.

**Three rules say what a `throws` clause names:**

- **Error types.** A type a function throws conforms to `Error`, a marker protocol with no requirements; `Never` conforms too.
- **Not throwing is throwing `Never`.** A function type that doesn't throw is the one that throws `Never` ([04](04-types.md#enums)). So a function value that doesn't throw binds a thrown type parameter to `Never`, as `abs` does below.
- **Inferred errors.** A non-public function with a body may write bare `throws`. For such a function, the compiler infers the union of the error types its body can throw, as it does for a closure literal. Where functions call each other in a cycle, it infers the smallest such union. A function type, a requirement and any other declaration without a body name their error type, since there is no body to infer it from.

```swift
func tryMap<E: Error>(_ xs: Span<Int>, _ f: (Int) throws(E) -> Int) throws(E) -> List<Int>
func square(_ x: Int) -> Int { x * x }
let squares = tryMap(xs, square)     // square throws nothing, so E is Never
```

### Error unions

A function that can fail for more than one reason names every error type in its `throws`:

```swift
func loadLevel(_ path: StringView) throws(IoError | ParseError) -> Level {
    let bytes = try readFile(path)            // throws IoError
    return try parseLevel(bytes)              // throws ParseError
}

struct LoadReport(var lastError: (IoError | ParseError)?)   // outside 'throws', a union is written in parentheses
typealias Failure = (IoError | ParseError)
```

**`throws(IoError | ParseError)` names an error union: a tagged union with one member per error type**, laid out like an enum whose cases carry the members.

- **One set, one type.** Members are flattened and deduplicated by identity, and ordered by their `T.id`s, which no two types share ([09](09-compile-time.md#what-reflection-can-read)), so the same set of types is the same type, with the same layout, everywhere in a program. `Never` is dropped from a union with other members, so `(Never | IoError)` is `IoError`, and a union of one type is that type.
- **An ordinary type.** Outside `throws` and a function type's parameters, a union is written in parentheses, as `lastError` and `Failure` are above. A value of one of its members, or of a union whose members it all has, converts to it implicitly, so assigning an `IoError` to `report.lastError` stores it ([05](05-protocols-generics-and-closures.md#implicit-conversions)). It conforms to `Error`, is `Copyable`, `Sendable`, `Frozen` and `TrivialFree` exactly when every member is, and is scoped when any member is. Like a Rayo enum, it is never `Pod`, since a tag that no member uses is no value of it ([04](04-types.md#plain-data-pod-and-bit-casts)). Its values are matched with the patterns of a `catch` ([below](#handling-errors-with-do-and-catch)).
- **Binding a type parameter in a union.** Where a union holds one type parameter, as `throws(E | IoError)` does, an argument binds it to the members of the argument's error type that the union's other members don't name, or to `Never` when none is left. So a closure that throws `(ParseError | IoError)` binds `E` to `ParseError`, and one that throws only `IoError`, or nothing, binds it to `Never`. A union holding two type parameters binds neither.

### Propagating errors with `try`

**`try f()` propagates, member by member**, and `throw e` throws `e`'s members the same way. When the enclosing function infers its errors, the members join that union unchanged. Otherwise each member must be the enclosing function's error type, or one of its members, or convert to it:

- **Conversion.** A member converts through the target type's `@converts` initializer whose single parameter is exactly that member, declared `owned`. The thrown value moves in, so the new error may carry what the thrown value borrowed, never a view of the thrown value itself ([02](02-views-and-dependencies.md#rule-5-the-callee-side)). A type may have one such initializer per source type, and it neither throws nor fails. It is declared in the target type's module or the source type's, and imports form no cycle, so only one of the two can see both types, and no two modules give one pair different conversions.
- **Into a union.** When the target is a union, a thrown member that is one of its members stays itself, and otherwise exactly one of its members may convert from it. If two could, the `try` or `throw` is an error.
- **A local lookup.** The lookup looks only at the target type, or for a generic error type at its constraints, so it stays bounded and local. With no matching initializer, the `try` is a compile error.

**`try?` and `try!`.** `try? f()` gives an optional. `try! f()` panics on an error.

**Conversions in generic code.** A protocol may require a conversion, and a `try` in generic code then converts through that requirement:

```swift
protocol FromIo: Error { @converts init(_ e: owned IoError) }   // every conforming error converts from IoError

func load<E: FromIo>(_ p: StringView) throws(E) -> List<UInt8> {
    let bytes = try readFile(p)        // readFile throws IoError: converted through E's requirement
    ...
}
```

### Handling errors with `do` and `catch`

```swift
do {
    let level = try loadLevel(path)           // the do block's error type: IoError | ParseError
    start(level)
} catch IoError.missing {                      // one case of one member, qualified by its type
    showMissingFileDialog()
} catch is IoError {                           // the rest of IoError
    showDiskErrorDialog()
} catch let e as ParseError {                  // a whole member, by type
    log("parse error at \(e.offset)")
}

func loadOrDefault(_ path: StringView) throws(IoError) -> Level {
    do {
        return try loadLevel(path)
    } catch is ParseError {                    // ParseError is handled here...
        return Level()
    }                                          // ...and IoError propagates, as a 'try' would
}
```

**A `do` block's error type is the union of what its body throws, and its `catch` clauses handle it member by member.**

- **Matching.** A clause matches one member by type (`catch let e as IoError`, `catch is ParseError`), or by one of its cases, with the patterns, `where` guards and coverage of a `when` arm ([04](04-types.md#matching-with-when-and-choosing-with-if)). An unqualified case, such as `.notFound`, must name a case of exactly one member, and otherwise must be qualified, as in `catch IoError.missing`. A `catch` with no pattern, or with `_` or `let e`, matches whatever the earlier clauses leave, and `let e` binds it as the union of the members it can be.
- **Exhaustiveness.** It is checked member by member, with a `when` arm's coverage. What no clause covers, whole members and the rest of a partly covered one, propagates from the `do` as a `try` would. Where nothing can propagate, in a function that doesn't throw or in a `defer` block, the clauses must cover every member.

### Cleanup

**These rules say when a `defer` block runs, and what its body may do:**

- **`defer { }` runs on every scope exit.** An error return is one, and it runs where the destruction order places it ([01](01-values-and-ownership.md#destruction)).
- **Control never leaves a `defer` block early.** A `return`, a `throw`, a `try` that propagates, and a `break` or `continue` that targets a loop outside the block are compile errors in it. It may call a function that never returns, such as `fatalError`.
- **A `defer` body is checked as if written at each point where it may run.** Those are every exit of its scope, a propagating `try` or `throw` included, and, in a `task` function, every `await` it is live across, where destroying the task runs it ([07](07-concurrency.md#semantics)). So it uses only what every one of those points allows.

## Panics

```swift
let e = enemies[h]!                              // panics if h is stale
precondition(count < capacity, "queue full")     // panics if the caller broke the contract
let share = total / players                      // panics if players is 0, in every build
```

**A panic is reported through the platform ([08](08-c-interop.md#what-the-runtime-needs-from-the-platform)), and never returns.** Nothing unwinds, so no frame's borrows end early, no `deinit` runs on a half-changed value, and work the panicking thread lent out still finds its memory ([13](13-soundness.md#checks-and-panics)).

### What panics

**The language and the runtime panic in the cases below, in every build unless noted, except where an `unchecked` block removes the check ([below](#unchecked-blocks)).**

**Failures the code asks for:**

- `fatalError("…")`, `precondition(cond, "…")`, `x!` on `nil`, `try!` on an error;
- a failing `assert(cond)`, where assertions are checked ([below](#assert-and-precondition));
- `unreachable()` reached.

**Arithmetic:**

- integer overflow, including unary `-` and `Int.min / -1`, an unlabeled integer conversion whose value doesn't fit, and an imported bitfield write that doesn't fit its width ([08](08-c-interop.md#structs-unions-and-enums)), only where overflow checks are on ([04](04-types.md#integer-overflow-division-and-shifts));
- division or remainder by zero, and converting NaN or an out-of-range floating-point value to an integer with the unlabeled form.

**Uses out of bounds, or outside a value's life:**

- out-of-bounds indexing, and a string range off a Unicode scalar boundary ([04](04-types.md#strings));
- an access through, or a pin taken through, a stale object owner ([03](03-handles-and-objects.md#destroying-an-object));
- opening an owning value whose allocator was reset or unregistered since ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it));
- reading a global before its initializer has run ([07](07-concurrency.md#initialization-at-startup));
- using a thread-local before its thread's copy is initialized or after it is destroyed ([07](07-concurrency.md#thread-locals));
- polling a task that has already finished ([07](07-concurrency.md#semantics)).

**Conflicting uses:**

- conflicting accesses to a thread-bound object ([03](03-handles-and-objects.md#dynamic-exclusivity)) or a thread-local ([07](07-concurrency.md#thread-locals));
- destroying a thread-bound object while an access to it is live ([03](03-handles-and-objects.md#destroying-an-object));
- taking a `Mutex`'s or an `RwLock`'s exclusive access on a thread that holds any access to it, or any access on a thread that holds its exclusive one, since that conflicts with a view the thread holds ([07](07-concurrency.md#locks-mutex-and-rwlock));
- `lock()` on a `Slice` of a bare `Shared<Blob>`, since nothing writes a `Frozen` value ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers));
- overlapping calls on one side of a single-producer or single-consumer queue, so that its algorithm never sees two producers or two consumers at once ([07](07-concurrency.md#queues-and-channels)).

**Running out:**

- running out of stack, each case caught before anything is written past the stack's end:
    - a call, or the destruction of deeply nested values, that needs more of the stack it runs on than is left, a fiber's stack that C declared included;
    - a call into C made with less stack left than its target declares, or than `target.cStackReserve` when it declares nothing ([08](08-c-interop.md#the-stack-a-c-call-needs));
- a count kept for safety that would overflow:
    - the reader counts of an object, a thread-local and an `RwLock` ([03](03-handles-and-objects.md#dynamic-exclusivity), [07](07-concurrency.md#locks-mutex-and-rwlock));
    - pin counts ([03](03-handles-and-objects.md#pinning-for-c));
    - a thread's counts of its uses of an allocator ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it));
    - the counts behind `Shared`, `LocalShared`, `Published` snapshots, and `Sender`, `Receiver` and `Future` values ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners), [07](07-concurrency.md#queues-and-channels));
- creating an object or a `Shared` value when no generation is left, so that no weak pointer or weak link names a later one ([03](03-handles-and-objects.md#destroying-an-object), [06](06-memory-and-allocators.md#sharedt-data-with-many-owners));
- an allocation that fails in a plain form, such as `UniquePointer(v)` or a closure context past the inline budget ([06](06-memory-and-allocators.md#allocation-failure)).

**Misused allocators:**

- any operation through an unregistered `Allocator` id, apart from the frees and growths that 06 allows from the `deinit`s its unregistration runs ([06](06-memory-and-allocators.md#unregistering-an-allocator));
- a reset or a `release` through an allocator that isn't an arena, since both are arena operations ([06](06-memory-and-allocators.md#what-a-reset-does));
- a reset past the implementation's limit on resets, so that no allocator word is issued twice ([06](06-memory-and-allocators.md#what-a-reset-does));
- a reset or an unregistration while anything still uses the memory it would free, or while another that reaches that memory is running ([06](06-memory-and-allocators.md#what-a-reset-does));
- unregistering `.system`, so that its storage never goes stale ([06](06-memory-and-allocators.md#allocator-values));
- registering an allocator whose backing is unregistered, or whose backing chain breaks a rule for backing chains ([06](06-memory-and-allocators.md#allocators-over-other-allocators));
- registering an allocator past the implementation's limit, so that no allocator word is issued twice ([06](06-memory-and-allocators.md#how-values-record-their-allocator)).

**Startup, shutdown and threads from C:**

- entering Rayo from C before startup has finished or after shutdown, except a nested entry ([07](07-concurrency.md#initialization-at-startup));
- calling `rayo_init` a second time, and detaching a thread or calling `rayo_shutdown` on a thread with a Rayo frame on any of its stacks, since those frames may still use what detaching or shutting down destroys ([08](08-c-interop.md#embedding-rayo-in-a-c-program));
- a wait during startup that would park with no timeout, since no other thread runs Rayo code during startup ([07](07-concurrency.md#initialization-at-startup)), and a thread queued during startup that the platform can't start when startup ends ([07](07-concurrency.md#starting-a-thread-runtimestartthread)).

**Names.** `Name(s)` panics when another text already has `s`'s hash, since no two texts share a `Name` ([04](04-types.md#collections-and-strings)).

### What a panic does

When a thread panics, on its own or with others:

- **The first panic is the one reported.** A thread that panics after it stops without reporting.
- **The program then ends, once the report is made.**
- **Every other thread stops.** Where the platform can suspend threads, each stops where it stands, lent work included, so the report can show its stack as it was. Elsewhere, each stops the next time it enters Rayo from C or parks, or when the program ends, so a thread deep in a long computation may run briefly after the panic.

### `assert` and `precondition`

```swift
mutating func push(_ item: owned Item) {
    precondition(count < capacity, "ring buffer full")    // an API contract: checked in every build
    assert(invariantsHold())                              // an internal invariant, costly to test: dev builds by default
    unsafe { (storage + tail).initialize(to: item) }      // relies on the precondition
    ...
}
```

**`precondition` checks a contract with the caller, and `assert` an internal invariant that may be costly to test.** Both panic when their condition is false, and they differ in which builds check them:

- **`assert(cond)`** is a diagnostic check, checked by default only in `dev` builds. A module or a scope can turn it on in any profile, through the build's settings or `@checks(.all)` ([below](#choosing-checks-for-a-module-or-a-scope)).
- **`precondition`** is checked in every build, and only `unchecked` code can strip it ([below](#unchecked-blocks)), so `unsafe` code after one may rely on its condition.

## Unsafe code

```swift
unsafe {
    let p: *Particle = ptr(to: &particles[0])
    p[3].pos = .zero
    memcpy(dst, src, n)
}
let now = unsafe plat.time_seconds()                                // one expression

unsafe func blit(_ dst: *UInt8, _ src: *UInt8, _ n: Int) { ... }   // callers need unsafe too
```

**An `unsafe` block marks code whose correctness the compiler takes on trust.** Checks stay as they are inside it, and `unchecked { }` turns them off ([below](#unchecked-blocks)).

**An `unsafe` block covers all the code written inside it, including the bodies of closure literals there.** `unsafe` before an expression is an `unsafe` block around its operand, as the precedence table of 12 binds it ([12](12-grammar.md#expressions)):

```swift
let sum = unsafe a.pointee + b.pointee      // error: 'unsafe' covers only a.pointee, and b.pointee needs it too
let total = unsafe (a.pointee + b.pointee)  // covers both reads
```

**The body of an `unsafe func` isn't an `unsafe` block.** It writes `unsafe` where it needs it, as any function does.

### What needs `unsafe`

**These operations need `unsafe`, since the compiler takes their correctness on trust:**

- dereferencing or offsetting a raw pointer, and converting an integer to a pointer ([below](#raw-pointers));
- taking an address with `ptr(to:)` ([below](#taking-an-address));
- the raw-memory operations ([below](#raw-memory)), and resizing or freeing a raw allocation ([below](#raw-allocations));
- calls into C, since a header can't say that a pointer outlives the call, or that a buffer holds `n` elements ([08](08-c-interop.md#calling-imported-functions));
- calls through `@c` pointers, since the type can't tell a Rayo function from a C one ([05](05-protocols-generics-and-closures.md#c-function-pointers)), and calls to `unsafe` functions;
- using a field declared `unsafe`, which `unsafe` code trusts, such as `Span`'s `baseAddress` ([02](02-views-and-dependencies.md#scoped-values)), whether by name, through reflection or as a `SoA` column;
- accessing a bare global `var` ([07](07-concurrency.md#global-state)) or an imported C variable ([08](08-c-interop.md#what-imports-as-what)), since every thread can reach it;
- converting a function to a `@c` type by C representations alone, or a `@c` value to a `@c noalloc` one ([05](05-protocols-generics-and-closures.md#c-function-pointers));
- reading a union member where 04 requires it, since what another member's write left there may not be a valid value of it ([04](04-types.md#untagged-unions)).

**No `unsafe` call is hidden**, so every promise that `unsafe` code makes is made at a visible `unsafe` site ([13](13-soundness.md#the-unsafe-boundary)).

- **An `unsafe` declaration** is used only inside `unsafe`, or through an `unsafe` function type, an `unsafe` requirement or a `: unsafe P` conformance. That holds for an `unsafe` declaration of any kind: a function, an initializer, an operator, a subscript or an accessor.
- **An imported or `extern c` function** is used only inside `unsafe`, or through a `@c` pointer, whose calls need `unsafe` ([05](05-protocols-generics-and-closures.md#c-function-pointers)).

So a call the language makes on the code's behalf is allowed only where the call written out would be. Examples are a `@converts` initializer under `try` ([above](#propagating-errors-with-try)), and the `==` of an expression pattern ([04](04-types.md#matching-with-when-and-choosing-with-if)).

### Raw pointers

**`*T` is a non-null raw pointer.** `*T?` is nullable, with the same size and ABI as a C pointer, since its `nil` is the null pointer ([04](04-types.md#optionals)).

- **Untyped pointers.** `*Void` points at memory of no stated type, and `p.cast(to: U.self)` converts between pointer types.
- **Integers.** Converting a pointer to an integer (`UInt(bitPattern: p)`) is safe. Converting an integer to a pointer is `unsafe`.
- **Reading and offsetting.** `p.pointee` is the `T` at `p`, `p + n` is `n` times `T`'s size further on, and `p[i]` is `(p + i).pointee`. They need a `T` whose size is known and nonzero. So `*Void` and a pointer to an `@opaque` type have none of them, and byte offsets go through `p.cast(to: UInt8.self)`.
- **Alignment.** Every type's size is a multiple of its alignment, so consecutive values stay aligned.

### What `unsafe` code upholds

**`unsafe` code keeps the rules of this section.** They are the invariants that make safe code free of undefined behavior, stated for `unsafe` code. Safe code keeps them by the rules of the other chapters, and its soundness assumes that `unsafe` code and C keep them too ([13](13-soundness.md#the-invariants)).

The rules say what an allocation is, what each access through a raw pointer must satisfy, and what the values and views that `unsafe` code leaves behind promise to the code that uses them.

#### Allocations

**Bounds and liveness are judged per allocation.** An **allocation** is one block of storage, which accesses stay inside and which is live or freed as a whole. It is one of these:

- storage that Rayo gave out from an allocator;
- the storage of a local, a temporary or a global, each one allocation;
- memory that C, the platform or a device provides, for as long as its provider keeps it.

**When an allocation is live:**

- **One from an allocator** is live until it is freed, by its owner or by a reset or an unregistration ([06](06-memory-and-allocators.md#what-a-reset-does)).
- **A local's or a temporary's** keeps one address, whatever moves into or out of it. It is live from the declaration or the creation to the end of its scope or full statement ([02](02-views-and-dependencies.md#temporaries)).
- **A `Closure`'s inline captures and a task's locals**, which its state holds across an `await` ([07](07-concurrency.md#semantics)), are the exception to keeping one address. They move with the value that holds them, so a pointer into them reaches what it pointed at only until that value next moves.

#### Raw accesses

**An access through a raw pointer must satisfy each of these, and breaking any of them is undefined behavior.** Together they say where the access may land, what it must find there, how much it may write, and how it is ordered against other threads:

- **In bounds.** `p + n` stays inside the allocation `p` was derived from, or one past its end. An access lies wholly inside that allocation while it is live, so nothing it reads or writes has been freed or reused ([13](13-soundness.md#the-invariants)).
- **Aligned.** The address is a multiple of `T`'s alignment, since a misaligned load or store faults on some targets ([04](04-types.md#packed-structs-and-under-aligned-places)).
- **Valid.** A read as `T` finds a valid `T` there. What is valid depends on the type:
    - for a padding-free `Pod` type ([04](04-types.md#plain-data-pod-and-bit-casts)), any initialized bytes;
    - for any other type, a bit pattern that is one of its values, such as a write of a `T` leaves;
    - for a type whose primary initializer or a field is `unsafe` or `private`, only the values its initializers could produce ([04](04-types.md#plain-data-pod-and-bit-casts)). Such a type may guard an invariant, such as a `Handle`'s generation that is never 0, and bytes must not forge a value that breaks it ([03](03-handles-and-objects.md#pools-and-handles)). So a `String`, `StringView` or `StaticString` holds whole UTF-8 sequences ([04](04-types.md#strings)).
- **Whole.** Storing a whole `T` may write every byte of it, padding included. So may any write to a `T` lent as a `mutable` argument, bound with `&` or reached through a `MutableSpan<T>`. A struct whose tail padding holds other data is never stored whole or lent in those ways, since such a write could overwrite the data in its padding. Its fields are written one by one, each through its own place, such as `p.pointee.len`. A `TrailingArray`'s header can be such a struct, and so can an imported struct whose flexible array member's elements share its tail padding ([04](04-types.md#variable-sized-structs-trailingarray)).
- **Race-free.** Two accesses to the same bytes on different threads, at least one of them a write, are ordered by synchronization ([07](07-concurrency.md#atomics-and-locks)). This doesn't apply when both are atomic accesses of the same size at the same address. Atomic accesses that overlap in any other way count as non-atomic here.
- **Exposed.** A pointer converted from an integer reaches only memory whose address was exposed:
    - an allocation whose address an earlier pointer-to-integer conversion exposed;
    - memory that Rayo didn't allocate, such as a device register at a fixed address, or a buffer whose address C passes as an integer.

**Raw accesses respect borrows and views.** `unsafe` code reads a place only where Rayo code could. It writes a place, moves its value out, as `p.move()` does, or destroys the value in it, only where Rayo code with exclusive access could. These rules apply the law of exclusivity ([01](01-values-and-ownership.md#the-law-of-exclusivity)) to raw accesses:

- **Under a mutable access.** While a `mutable` access, an `&` binding or a mutable view is live, nothing touches the places it reaches except through it. So two `MutableSpan`s made from one pointer never overlap while both are live, since one could write what the other still reads ([02](02-views-and-dependencies.md#mutable-views)).
- **Under a borrow.** While a borrow, a `let` of a place or a shared view is live, nothing writes, moves out of or destroys the places it reads. The exception is the places inside a `Synchronized` value, which its own operations may write, move out of or destroy. Any other write could free what the borrow still reads, as appending to a `String` may move its text and free the buffer a view of it reads ([13](13-soundness.md)).
- **Immutable memory.** Nothing writes memory that Rayo treats as immutable: read-only data, which holds every `const`'s frozen data, and a `Frozen` value behind a `Shared` or a `LocalShared`. Rayo reads such memory without a mark ([08](08-c-interop.md#what-c-must-uphold)). Nothing writes memory that its provider made read-only either, such as a C object defined `const`, a string literal's bytes or a page mapped read-only.

**A live parameter counts as a borrow or `mutable` access of its argument's place.** The compiler may assume that neither kind is aliased. It may also pass a borrowed argument as a copy of its bits, so the callee may see a copy rather than the caller's place ([01](01-values-and-ownership.md#borrowed-arguments)).

**The views `unsafe` code makes keep the promises that 02 states for dependencies** ([02](02-views-and-dependencies.md#dependencies)). The compiler sees names, not memory, so a view's dependency set is all it knows of which places the view reaches ([13](13-soundness.md#dependencies)).

#### Values, views and threads

**These rules cover the values, views and threads that `unsafe` code hands on to other code:**

- **Places hold valid values.** Whenever Rayo code may next read, lend or destroy a place as `T`, it holds a valid `T`. So a write through a pointer of another type leaves one there. A place that `p.move()` or `p.deinitialize()` emptied is initialized again before its owner uses or destroys it. Otherwise the owner would use or destroy a value that has moved out or been destroyed already ([13](13-soundness.md#the-invariants)).
- **Views reach live, aligned, valid places.** This holds for a span, `Borrow` or `MutableRef` that `unsafe` code makes from a raw pointer, and for a borrowed or `mutable` argument that it passes through one. For as long as such a view or argument lives, its places lie inside one live allocation, and each is aligned for its type and holds a valid value. Such a mutable view's places, and such a `mutable` argument's, are also writable. A span reaches its `count` consecutive places. Safe code reads and writes them with aligned accesses.
- **A move-only value has one owner.** Its bytes stand for one value. After they are copied to a second place, only one of the two is used or destroyed as that type again, as `p.move()` leaves only the destination. Two places standing for it would be two owners of what it holds, two mutable aliases, or a guard that unlocks twice ([13](13-soundness.md#ownership)).
- **A panic leaves shared state valid.** Wherever `unsafe` code can panic, what other threads can reach through it is valid, as if the code had stopped there, since other threads may run briefly after a panic ([above](#what-a-panic-does)). A queue's links and a lock's word are such state.
- **Values that aren't `Sendable` stay on their thread.** Such a value is used, lent and destroyed only on the thread whose code made it, or, for a thread-bound object, on its home thread ([07](07-concurrency.md#what-may-cross-threads-sendable)). That holds whatever `unsafe` code or C passes it through, since only on that thread do exclusivity and the dynamic tier check all of its aliases ([07](07-concurrency.md#why-safe-code-cant-race)). A value that only the raw pointers it holds keep from being `Sendable` may cross, and each access through those pointers follows the rules on raw accesses ([above](#raw-accesses)).

### Aliasing and skipped `deinit`s

Two more facts are part of the boundary between `unsafe` and safe code ([13](13-soundness.md#the-unsafe-boundary)):

**Memory has no declared type.** A raw pointer of any type may alias memory also reached as another type, and `unsafe` code may rely on that.

**A `deinit` may never run, and `unsafe` code allows for that.** Destroying a stale value skips its elements' `deinit`s ([06](06-memory-and-allocators.md#stale-values-and-the-deinits-a-reset-runs)). So `unsafe` code stays sound when a value it hands out, a guard included, is never destroyed. A guard left in a stale container, for one, keeps its lock held, and moving or destroying that lock stays sound ([07](07-concurrency.md#the-synchronized-contract)).

### Taking an address

**`ptr(to:)` returns the address of a place**, in two forms: one for a place lent to it with `&`, and a shared form for a place it borrows.

```swift
unsafe func ptr<T>(to place: mutable T) -> *T     // the form for a place lent with '&'
let p = unsafe ptr(to: &particles[0])             // the address of particles[0], lent for change
let q = unsafe ptr(to: particles[0])              // the shared form: the address of a place it borrows
```

- **Builtin.** It is builtin, and the call's `&` chooses the form, as for a method's forms ([04](04-types.md#shared-mutable-and-consuming-forms-of-one-method)).
- **Never a function value.** It converts to no function type or `Closure` and binds no `some F`, so every call of it is direct.
- **The caller's place.** Its argument, borrowed or not, is always the caller's place, never a copy, since its result is that place's address ([01](01-values-and-ownership.md#borrowed-arguments)).
- **A short access.** The access ends with the call, since a raw pointer is unscoped.

**The place must be storage that a view could outlive:** a variable, a stored field or element, or a storage projection ([02](02-views-and-dependencies.md#storage-projections)). Passing an access-bound projection or an under-aligned place ([04](04-types.md#packed-structs-and-under-aligned-places)) is a compile error, since either reaches the call only as a temporary the call would outlive. An under-aligned field's address is its enclosing place's plus `field.offset` ([09](09-compile-time.md#what-reflection-can-read)).

**An object's value or a thread-local qualifies, but no mark guards later uses of its address.** The dynamic access the call takes ends with the call. Later uses of the address keep the rules on raw accesses ([above](#raw-accesses)). They stay in bounds only while the object, or the thread's copy, lives.

### Raw memory

**The raw-memory operations put a value in, take it out, or destroy it in place:**

- `p.initialize(to: v)` moves `v` into uninitialized memory without running a `deinit` on what was there.
- `p.move()` moves the value out and leaves the memory uninitialized.
- `p.deinitialize()` destroys the value in place, running its `deinit` and its fields'. `p.deinitialize(count: n)` does so for `n` values.

Plain assignment through `p.pointee` assumes initialized memory and destroys the old value first, as for any place.

### Raw allocations

**`allocator.allocateRaw(bytes:align:)` returns a `RawAllocation`, or `nil` when the allocator can't make it.** A `RawAllocation` is a copyable record of these:

- the address, an `unsafe` field, so safe code never sees it;
- the size and the alignment;
- the allocator word ([06](06-memory-and-allocators.md#how-values-record-their-allocator)).

**Resizing and freeing:**

- `reallocateRaw(_:bytes:)` resizes one, keeping its first bytes up to the smaller size, and returns the updated record. It returns `nil` when the allocator can't make the new size, which leaves the old allocation live and unchanged.
- `freeRaw(_:)` gives one back.

**`reallocateRaw` and `freeRaw` are `unsafe`, and reach the allocator through the record's word.** Their caller promises that the word names the allocator they are called on, and that the allocation is still live. After `freeRaw`, the caller uses nothing at the old address. After a `reallocateRaw` that succeeds, it uses the allocation only through the record that call returned.

**An `unsafe` core, an owning container that user `unsafe` code builds on raw allocations, checks the word before it touches the storage.** It stores the word next to its pointer. It checks the word at every open, each access that reaches the storage ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)), before it reads, writes or frees there. The check is made at the open, since a reset can't find the values it invalidates, which may be anywhere. `word.isLive` makes that check without panicking, so the core can refuse a stale buffer instead of reading reused memory.

### Hardware access

**These operations serve hardware access and code that interrupts a thread:**

- `volatileLoad(p)` and `volatileStore(p, v)`, for a `T` of 1, 2, 4 or 8 bytes, are each performed exactly once, at `T`'s width, and in program order with the thread's other volatile accesses. They are never merged, split or removed.
- `fence(_:)`, given `.acquire`, `.release`, `.acqRel` or `.seqCst`, is a memory fence of that ordering ([07](07-concurrency.md#atomics-and-locks)).
- `compilerFence(_:)` orders the thread's accesses only against code interrupting that same thread, such as a signal handler.

### `@safe` modules

**A module the build declares `@safe` ([09](09-compile-time.md#what-a-build-declares)) is restricted to the safe subset.** Every construct whose correctness the compiler takes on trust is an error anywhere in it. It can still call safe wrappers that other modules built with `unsafe`. So it makes no promise of its own, and is sound given the modules it calls ([13](13-soundness.md#the-unsafe-boundary)).

**A `@safe` module rejects:**

- `unsafe` blocks, expressions and functions;
- the unverified promises ([below](#unverified-promises)): `unsafe` conformances, `@pod`, `@export` functions, `import c` config blocks and `extern c func` declarations;
- `unchecked` blocks ([below](#unchecked-blocks));
- `extern c` blocks of C code ([08](08-c-interop.md#inline-c)).

#### Unverified promises

**The unverified promises are these, each taken on trust:**

- **`@pod`** states that every bit pattern of a struct or union is valid ([04](04-types.md#plain-data-pod-and-bit-casts)). It waives the visibility and `unsafe` conditions, which keep bytes from forging a value whose invariant a type guards.
- **`@export` on a function** is a promise about its C name and callers ([08](08-c-interop.md#calling-rayo-from-c)).
- **A conformance to an `unsafe protocol`** is a contract the compiler can't check ([05](05-protocols-generics-and-closures.md#conformances)). An **unsafe protocol** is one declared with `unsafe protocol`. A conformance the compiler derives itself, such as `Frozen` for a type with no interior mutability, or `Sendable` for a type whose fields are all `Sendable`, is no promise. The language's own unsafe protocols are these:
    - `Sendable` and `Synchronized` ([07](07-concurrency.md));
    - `Frozen` and `AllocatorImpl` ([06](06-memory-and-allocators.md));
    - `PlainDeinit` ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)).
- **A conformance written `: unsafe P` for one of these reasons** is a promise too, since generic code reaches a witness with no `unsafe` in sight ([05](05-protocols-generics-and-closures.md#conformances)):
    - a witness is an `unsafe` field, or a union member that isn't safe to read;
    - a witness is a static stored `var` that isn't `@threadlocal`, which also promises that its accesses never race;
    - a witness is an `unsafe` declaration meeting a safe requirement;
    - its derived `==` or `hash(into:)` reads such a field or member ([05](05-protocols-generics-and-closures.md#equality-and-ordering)).
- **A rule in an `import c` config block** is an assertion about the header's C. The rules are `noalloc` ([08](08-c-interop.md#c-calls-in-noalloc-code-noalloc)), `stack` ([08](08-c-interop.md#the-stack-a-c-call-needs)), and `struct`, `union` or `enum S in "h"` ([08](08-c-interop.md#the-identity-of-an-imported-type)). A `stack` in a `@c` function pointer type is no promise, since a function converts to the type only when the type declares at least the function's need.
- **An `extern c func` declaration** is an assertion about its module's `extern c` code or a linked library ([08](08-c-interop.md#inline-c)).

## Check levels

```swift
let v = verts[i]          // bounds check: without it, a bad index would read memory outside the buffer
let n = a + b             // overflow check: without it, the sum wraps, which is a wrong value but memory-safe
```

**Checks come in two classes:**

- **Memory-safety checks**, bounds checks among them, make safe code sound. They are on in every build, and only `unchecked` code can strip them ([below](#unchecked-blocks)).
- **Diagnostic checks** catch logic bugs whose failure is still memory-safe, such as wrapping arithmetic. With one off, a wrong value still meets every memory-safety check, as a wrapped index meets the next bounds check ([13](13-soundness.md#checks-and-panics)).

**Each diagnostic check is on or off where code is written.** The innermost of these decides it:

- an enclosing `@checks` ([below](#choosing-checks-for-a-module-or-a-scope));
- the module's settings;
- the profile's default ([below](#build-profiles)).

An enclosing `unchecked` block turns every one off ([below](#unchecked-blocks)). `target.checks` holds those that are on ([09](09-compile-time.md#static-if-and-conditional-compilation)).

### Choosing checks for a module or a scope

```swift
@checks(.all) func accumulate(_ total: mutable Int, _ xs: Span<Int>) { … }   // overflow checked here, even in ship
@checks(.none) do { for x in xs { sum += x } }                            // diagnostics off in this block only; bounds stay on
```

**Diagnostic checks can be chosen per module and per scope.**

- **Per scope**, for a function, a type's members or a `do` block, with `@checks(…)`. It takes `.all`, `.none`, or a set of the diagnostic checks, which are `.overflow` and `.assert` ([below](#the-checks)), as in `@checks([.overflow])`. It sets exactly those on for its scope, replacing what encloses it.
- **Per module**, with the same values, in the build's settings ([09](09-compile-time.md#what-a-build-declares)).
- **In `@safe` modules too**, since they only choose diagnostic checks.

### `unchecked` blocks

```swift
unchecked {                        // bounds and the table's other checks off here
    for i in 0..<n { dst[i] = src[i] * k }
}
```

**An `unchecked` block removes every check in the table below that its code performs.** Its code is the code written inside it, and the bodies of the `@inline` functions it calls, such as a collection's subscript, which become part of it ([11](11-compilation-model.md#functions-that-are-never-calls-inline)).

**It leaves these in place:**

- the checks of the other functions it calls;
- the panics that the table doesn't list ([above](#what-panics));
- synchronization, since a lock and an atomic operation are the operation itself;
- the memory ordering of a check that also orders memory, as a single-sided queue's side check does ([07](07-concurrency.md#queues-and-channels)). Only its failure test is removed.

**A removed diagnostic check acts as where it is off, and any other removed check's failure is undefined behavior.** So an overflow wraps or truncates, and `assert` doesn't evaluate its condition.

### The checks

| Check | Class | `dev` | `profile` | `ship` |
| --- | --- | --- | --- | --- |
| Indexing and slicing bounds, and string ranges on Unicode scalar boundaries | memory safety | on | on | on |
| Stack space, on entry to each function and before each call into C | memory safety | on | on | on |
| Thread-bound object: liveness, conflicting accesses, and destruction under an access | memory safety | on | on | on |
| Thread-local: initialized, not destroyed, and conflicting accesses | memory safety | on | on | on |
| Opening an owning value whose storage a reset or an unregistration invalidated | memory safety | on | on | on |
| Safety counts: reader, pin, owner and allocator-use counts | memory safety | on | on | on |
| `Slice` of a locked blob or `List`: current length and alignment, or current count | memory safety | on | on | on |
| Taking a `Mutex`'s or an `RwLock`'s exclusive access on a thread that holds either kind, or either kind on a thread that holds the exclusive one | memory safety | on | on | on |
| Single-producer and single-consumer queues: overlapping calls on one side | memory safety | on | on | on |
| Reading a global before its initializer has run | memory safety | on | on | on |
| Entry from C before startup or after shutdown | memory safety | on | on | on |
| Polling a finished task | memory safety | on | on | on |
| Integer division and remainder by zero, and float-to-integer conversion of NaN or an out-of-range value | memory safety | on | on | on |
| Integer overflow on `+ - *`, unary `-`, `Int.min / -1`, unlabeled integer conversions whose value doesn't fit, and imported bitfield writes that don't fit the width ([08](08-c-interop.md#structs-unions-and-enums)) | diagnostic | on | on | off: wraps or truncates ([04](04-types.md#integer-overflow-division-and-shifts)) |
| `x!` on `nil`, and `try!` on an error | memory safety | on | on | on |
| `precondition` | memory safety | on | on | on |
| `unreachable()` reached | memory safety | on | on | on |
| `assert` | diagnostic | on | off | off |

**Division by zero, the float-to-integer conversions, `!`, `try!` and `unreachable()` count as memory safety, since, unchecked, their failure is undefined behavior.** `precondition` counts as memory safety since `unsafe` code may rely on it.

## Build profiles

**The build profiles are `dev`, `profile` and `ship`, a closed set.** Each sets the default for the diagnostic checks, as the table above gives it ([above](#the-checks)). A build that names none uses `ship`.
