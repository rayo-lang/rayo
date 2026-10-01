# 11 · Errors and safety

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
    case unknownCase(Name)                  // reflective loaders (10)
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

- **Error types.** A type a function throws conforms to `Error`, a marker protocol with no requirements; `Never` conforms too.
- **Not throwing is throwing `Never`.** A function type that doesn't throw is the one that throws `Never` ([04](04-types.md#enums)), so a non-throwing function value binds a thrown type parameter to `Never`, as `tryMap(xs, abs)` does for `func tryMap<E: Error>(_ xs: Span<Int>, _ f: (Int) throws(E) -> Int) throws(E) -> List<Int>`.
- **Inferred errors.** A non-public function with a body may write bare `throws`, and the compiler infers the union of the error types its body can throw, as it does for a closure literal, the smallest such union where functions call each other in a cycle. A function type, a requirement and any other declaration without a body name their error type.

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

- **One set, one type.** Members are flattened and deduplicated by identity, and ordered by their `T.id`s, which no two types share ([10](10-compile-time.md#what-reflection-can-read)), so the same set of types is the same type, with the same layout, everywhere in a program. `Never` is dropped from a union with other members, so `(Never | IoError)` is `IoError`, and a union of one type is that type.
- **An ordinary type.** Outside `throws` and a function type's parameters, a union is written in parentheses, as `lastError` and `Failure` are above. A value of one of its members, or of a union whose members it all has, converts to it implicitly, so `report.lastError = e` stores an `IoError` ([05](05-protocols-generics-and-closures.md#implicit-conversions)). It conforms to `Error`, is `Copyable`, `Sendable`, `Frozen` and `TrivialFree` exactly when every member is, and is scoped when any member is. Like a Rayo enum, it is never `Pod`, since a tag that no member uses is no value of it ([04](04-types.md#plain-data-pod-and-bit-casts)). Its values are matched with the patterns of a `catch` ([below](#handling-errors-with-do-and-catch)).
- **Binding a type parameter in a union.** Where a union holds one type parameter, as `throws(E | IoError)` does, an argument binds it to the members of the argument's error type that the union's other members don't name, or to `Never` when none is left: a closure that throws `(ParseError | IoError)` binds `E` to `ParseError`, and one that throws only `IoError`, or nothing, binds it to `Never`. A union holding two type parameters binds neither.

### Propagating errors with `try`

**`try f()` propagates, member by member**, and `throw e` throws `e`'s members the same way. When the enclosing function infers its errors, the members join that union unchanged. Otherwise each member must be the enclosing function's error type, or one of its members, or convert to it:

- **Conversion.** A member converts through the target type's `@converts` initializer whose single parameter is exactly that member, declared `owned`: the thrown value moves in, so the new error may carry what the thrown value borrowed, never a view of the thrown value itself ([02](02-views-and-dependencies.md#dependencies)). A type may have one such initializer per source type, and it neither throws nor fails. It is declared in the target type's module or the source type's, and imports form no cycle, so only one of the two can see both types, and no two modules give one pair different conversions.
- **Into a union.** When the target is a union, a thrown member that is one of its members stays itself, and otherwise exactly one of its members may convert from it. If two could, the `try` or `throw` is an error.
- **A local lookup.** The lookup looks only at the target type, or for a generic error type at its constraints, so it stays bounded and local. With no matching initializer, the `try` is a compile error.

**`try?` and `try!`.** `try? f()` gives an optional. `try! f()` panics on an error.

**Conversions in generic code.** A protocol may require a conversion, as in `protocol FromIo: Error { @converts init(_ e: owned IoError) }`. Then in `func load<E: FromIo>(_ p: StringView) throws(E) -> Bytes`, `try readFile(p)` converts through `E`'s requirement.

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

- **`defer { }` runs on every scope exit.** An error return is one, and it runs where [01](01-values-and-ownership.md#values)'s destruction order places it.
- **Control never leaves a `defer` block early.** A `return`, a `throw`, a `try` that propagates, and a `break` or `continue` that targets a loop outside the block are compile errors in it. It may call a function that never returns, such as `fatalError`.
- **A `defer` body is checked as if written at each point where it may run.** Those are every exit of its scope, a propagating `try` or `throw` included, and, in a `task` function, every `await` it is live across, where destroying the task runs it ([07](07-concurrency.md#semantics)). So it uses only what every one of those points allows.

## Panics

```swift
let e = enemies[h]!                              // panics if h is stale
precondition(count < capacity, "queue full")     // panics if the caller broke the contract
let share = total / players                      // panics if players is 0, in every build
```

**A panic is reported through the platform ([09](09-c-interop.md#what-the-runtime-needs-from-the-platform)), and never returns.**

### What panics

The language and the runtime panic on the following, in every build unless noted, except where an `unchecked` block removes the check ([below](#check-levels)):

- `fatalError("…")`, `precondition(cond, "…")`, `x!` on `nil`, `try!` on an error;
- a failing `assert(cond)`, where assertions are checked ([below](#assert-and-precondition));
- out-of-bounds indexing, and a string range off a Unicode scalar boundary ([04](04-types.md#strings));
- integer overflow, including unary `-` and `Int.min / -1`, an unlabeled integer conversion whose value doesn't fit, and an imported bitfield write that doesn't fit its width ([09](09-c-interop.md#structs-unions-and-enums)), only where overflow checks are on ([04](04-types.md#integer-overflow-division-and-shifts));
- division or remainder by zero, and converting NaN or an out-of-range floating-point value to an integer with the unlabeled form;
- an access through, or a pin taken through, a stale object owner, opening an owning value whose allocator was reset or unregistered since ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)), and conflicting accesses to a thread-bound object or a thread-local;
- running out of stack: a call, or the destruction of deeply nested values, that needs more of the stack it runs on than is left, a fiber's stack that C declared included, and a call into C made with less stack left than its target declares, or than `target.cStackReserve` when it declares nothing ([09](09-c-interop.md#the-stack-a-c-call-needs)), each caught before anything is written past the stack's end;
- a count kept for safety that would overflow: the reader counts of an object, a thread-local and an `RwLock` ([03](03-handles-and-objects.md#dynamic-exclusivity), [07](07-concurrency.md#locks-mutex-and-rwlock)), pin counts ([03](03-handles-and-objects.md#pinning-for-c)), and the counts behind `Shared`, `LocalShared`, `Published` snapshots, and `Sender`, `Receiver` and `Future` values ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners), [07](07-concurrency.md#queues-and-channels)); and creating an object or a `Shared` value when no generation is left ([03](03-handles-and-objects.md#destroying-an-object), [06](06-memory-and-allocators.md#sharedt-data-with-many-owners));
- an allocation that fails in a plain form, such as `UniquePointer(v)` or a closure context past the inline budget ([06](06-memory-and-allocators.md#allocation-failure));
- any operation through an unregistered `Allocator` id, apart from the frees and growths that [06](06-memory-and-allocators.md#unregistering-an-allocator) allows from the `deinit`s its unregistration retired, a reset or a `release` through one that isn't an arena, a reset past the implementation's limit on resets ([06](06-memory-and-allocators.md#what-a-reset-does)), unregistering `.system` ([06](06-memory-and-allocators.md#unregistering-an-allocator)), and registering an allocator whose backing is unregistered, whose backing chain breaks a rule of [06](06-memory-and-allocators.md#allocators-over-other-allocators), or past the implementation's limit ([06](06-memory-and-allocators.md#how-values-record-their-allocator));
- taking a lock's exclusive access on a thread that holds either kind of access to it, or either kind on a thread that holds its exclusive one, for a `Mutex` or an `RwLock` ([07](07-concurrency.md#locks-mutex-and-rwlock)), and `lock()` on a `Slice` of a bare `Shared<Blob>` ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers));
- overlapping calls on one side of a single-producer or single-consumer queue ([07](07-concurrency.md#queues-and-channels));
- reading a global before its initializer has run, and using a thread-local before its thread's copy is initialized or after it is destroyed;
- entering Rayo from C before startup has finished or after shutdown, except a nested entry, which goes one depth deeper or parks for good ([07](07-concurrency.md#initialization-at-startup)), calling `rayo_init` a second time, and detaching a thread or calling `rayo_shutdown` on a thread with a Rayo frame on any of its stacks ([09](09-c-interop.md#embedding-rayo-in-a-c-program));
- a wait during startup that would park with no timeout ([07](07-concurrency.md#initialization-at-startup)), and a thread queued during startup that the platform can't start when startup ends ([07](07-concurrency.md#starting-a-thread-runtimestartthread));
- polling a task that has already finished ([07](07-concurrency.md#semantics));
- interning a `Name` whose hash another text already has ([04](04-types.md#collections-and-strings));
- `unreachable()` reached.

### What a panic does

When a thread panics, on its own or with others:

- **The first panic is the one reported.** A thread that panics after it stops without reporting.
- **The program then ends, once the report is made.**
- **Every other thread stops.** Where the platform can suspend threads, each stops where it stands, lent work included, so the report can show its stack as it was. Elsewhere, each stops at its next section entry, checkpoint or parking wait, so a thread deep in a long section may run briefly after the panic.

### `assert` and `precondition`

```swift
mutating func push(_ item: owned Item) {
    precondition(count < capacity, "ring buffer full")    // an API contract: checked in every build
    assert(invariantsHold())                              // an internal invariant, costly to test: dev builds by default
    unsafe { (storage + tail).initialize(to: item) }      // relies on the precondition
    ...
}
```

- `assert(cond)` is a diagnostic check, checked by default only in `dev` builds. A module or a scope can turn it on in any profile, through the build's settings or `@checks(.all)` ([below](#choosing-checks-for-a-module-or-a-scope)).
- `precondition` is checked in every build, and only `unchecked` code can strip it ([below](#check-levels)), so `unsafe` code after one may rely on its condition.

## Unsafe code

These need `unsafe`: dereferencing or offsetting a raw pointer, converting an integer to a pointer, taking an address with `ptr(to:)`, the raw-memory operations, and resizing or freeing a raw allocation (below); calls into C, through `@c` pointers, and to `unsafe` functions; using a field declared `unsafe`, such as `Span`'s `baseAddress` ([02](02-views-and-dependencies.md#scoped-values)), by name, through reflection or as a `SoA` column; accessing a bare global `var` ([07](07-concurrency.md#global-state)) or an imported C variable ([09](09-c-interop.md#what-imports-as-what)); converting a function to a `@c` type by C representations alone, or a `@c` value to a `@c noalloc` one ([05](05-protocols-generics-and-closures.md#c-function-pointers)); and reading a union member where [04](04-types.md#untagged-unions) requires it:

```swift
unsafe {
    let p: *Particle = ptr(to: &particles[0])
    p[3].pos = .zero
    memcpy(dst, src, n)
}
let now = unsafe plat.time_seconds()                                // one expression

unsafe func blit(_ dst: *UInt8, _ src: *UInt8, _ n: Int) { ... }   // callers need unsafe too
```

`unsafe` before an expression is an `unsafe` block around its operand, as the precedence table of [13](13-grammar.md#expressions) binds it, so `unsafe a.pointee + b.pointee` covers only `a.pointee`. A block covers all the code written inside it, including the bodies of closure literals there. An `unsafe func`'s body is no `unsafe` block: it writes `unsafe` where it needs it, as any function does.

**No `unsafe` call is hidden.** An `unsafe` declaration of any kind, a function, initializer, operator, subscript or accessor, is used only inside `unsafe`, or through an `unsafe` function type, an `unsafe` requirement or a `: unsafe P` conformance. An imported or `extern c` function is used only inside `unsafe`, or through a `@c` pointer, whose calls need `unsafe` ([05](05-protocols-generics-and-closures.md#c-function-pointers)). So a call the language makes on the code's behalf, such as a `@converts` initializer under `try` ([above](#propagating-errors-with-try)) or the `==` of an expression pattern ([04](04-types.md#matching-with-when-and-choosing-with-if)), is allowed only where the call written out would be.

An `unsafe` block marks code whose correctness the compiler takes on trust. Checks stay as they are inside it, and `unchecked { }` turns them off ([below](#check-levels)).

**Pointers.**

- `*T` is a non-null raw pointer. `*T?` is nullable, with the same size and ABI as a C pointer.
- `*Void` points at memory of no stated type, and `p.cast(to: U.self)` converts between pointer types. Converting a pointer to an integer (`UInt(bitPattern: p)`) is safe; converting an integer to a pointer is `unsafe`.
- `p.pointee` is the `T` at `p`, `p + n` is `n` times `T`'s size further on, and `p[i]` is `(p + i).pointee`. Every type's size is a multiple of its alignment, so consecutive values stay aligned. They need a `T` whose size is known and nonzero, so `*Void` and a pointer to an `@opaque` type have none of them, and byte offsets go through `p.cast(to: UInt8.self)`.

**What `unsafe` code upholds.**

- **What an access through a raw pointer must satisfy.** Breaking any of these is undefined behavior:
    - **In bounds.** `p + n` stays inside the allocation `p` was derived from, or one past its end, and an access lies wholly inside that allocation while it is live. An **allocation** is storage Rayo gave out, from an allocator or as a local, a temporary or a global, each one allocation, or memory that C, the platform or a device provides, for as long as its provider keeps it. One from an allocator is live until it is freed, or, when a reset or unregistration retires it, until the runtime releases its memory once a grace period has passed ([06](06-memory-and-allocators.md#what-a-reset-does)). A local's or temporary's keeps one address and is live from its declaration or creation to the end of its scope or full statement ([02](02-views-and-dependencies.md#dependencies)), whatever moves into or out of it, except storage inside a value that moves: a `Closure`'s inline captures, and a task's locals, which its state holds across an `await` ([07](07-concurrency.md#semantics)), move with that value, so a pointer into them reaches what it pointed at only until the value next moves.
    - **Aligned.** The address is a multiple of `T`'s alignment.
    - **Valid.** A read as `T` finds a valid `T` there: any initialized bytes, for a padding-free `Pod` type ([04](04-types.md#plain-data-pod-and-bit-casts)), and for any other type a bit pattern that is one of its values, such as a write of a `T` leaves. For a type whose primary initializer or a field is `unsafe` or `private`, its values are only those its initializers could produce ([04](04-types.md#plain-data-pod-and-bit-casts)). So a `String`, `StringView` or `StaticString` holds whole UTF-8 sequences ([04](04-types.md#strings)).
    - **Whole.** Storing a whole `T` may write every byte of it, padding included, and so may any write to a `T` lent as a `mutable` argument, bound with `&` or reached through a `MutableSpan<T>`. So a struct whose tail padding holds other data, such as a `TrailingArray`'s header or an imported struct with a flexible array member ([04](04-types.md#variable-sized-structs-trailingarray)), is never stored whole or lent in those ways: its fields are written one by one, as in `p.pointee.len = 9`.
    - **Race-free.** Two accesses to the same bytes on different threads, at least one of them a write, are ordered by synchronization ([07](07-concurrency.md#atomics-and-locks)) unless both are atomic accesses of the same size at the same address. Atomic accesses that overlap in any other way count as non-atomic here.
    - **Exposed.** A pointer converted from an integer reaches only memory whose address was exposed: an allocation whose address an earlier pointer-to-integer conversion exposed, or memory that Rayo didn't allocate, such as a device register at a fixed address or a buffer whose address C passes as an integer.
- **Places hold valid values.** Whenever Rayo code may next read, lend or destroy a place as `T`, it holds a valid `T`. So a write through a pointer of another type leaves one there, and a place that `p.move()` or `p.deinitialize()` emptied is initialized again before its owner uses or destroys it.
- **Views reach aligned places.** A span, `Borrow` or `MutableRef` that `unsafe` code makes from a raw pointer, and a borrowed or `mutable` argument that it passes through one, reaches, for as long as it lives, places inside a live allocation, each aligned for its type and holding a valid value, and writable for a mutable view or a `mutable` argument: a span its `count` consecutive places. Safe code reads and writes them with aligned accesses.
- **A move-only value has one owner.** Its bytes stand for one value, so after they are copied to a second place, only one of the two is used or destroyed as that type again, as `p.move()` leaves only the destination.
- **A panic leaves shared state valid.** Other threads may run briefly after a panic ([above](#what-a-panic-does)), so wherever `unsafe` code can panic, what other threads can reach through it, such as a queue's links or a lock's word, is valid, as if the code had stopped there.
- **Values that aren't `Sendable` stay on their thread.** Such a value is used, lent and destroyed only on the thread whose code made it, or, for a thread-bound object, its home thread ([07](07-concurrency.md#what-may-cross-threads-sendable)), whatever `unsafe` code or C passes it through. A value that nothing but the raw pointers it holds keeps from being `Sendable` may cross, and each access through those pointers follows the rules above.
- **Raw accesses respect borrows and views.** `unsafe` code reads a place only where Rayo code could, and writes it, moves its value out, as `p.move()` does, or destroys the value in it, only where Rayo code with exclusive access could:
    - while a `mutable` access, an `&` binding or a mutable view is live, nothing touches the places it reaches except through it, so two `MutableSpan`s made from one pointer never overlap while both are live;
    - while a borrow, a `let` of a place or a shared view is live, nothing writes, moves out of or destroys the places it reads, except inside a `Synchronized` value, through its own operations;
    - nothing writes memory that Rayo treats as immutable (static data, a `const`'s frozen data, and a `Frozen` value behind a `Shared` or a `LocalShared`) or that its provider made read-only, such as a C object defined `const`, a string literal's bytes or a page mapped read-only.

    A live parameter counts as a borrow or `mutable` access of its argument's place, since a borrowed argument may be passed as a copy ([01](01-values-and-ownership.md#parameters)) and the compiler may assume neither kind is aliased. The views `unsafe` code makes also keep [02](02-views-and-dependencies.md#dependencies)'s promises.

**What `unsafe` code may rely on, and must allow for.**

- **Memory has no declared type.** A raw pointer of any type may alias memory also reached as another type.
- **A `deinit` may never run.** Destroying a stale value skips its elements' `deinit`s ([06](06-memory-and-allocators.md#stale-values-and-retired-objects)), so `unsafe` code stays sound when a value it hands out, a guard included, is never destroyed.

**Taking an address.** `unsafe func ptr<T>(to place: mutable T) -> *T` returns the address of the place lent to it, as in `ptr(to: &particles[0])`, and its shared form, `ptr(to: x)`, of a place it borrows. It is builtin, and the call's `&` chooses the form, as for a method's forms ([04](04-types.md#shared-mutable-and-consuming-forms-of-one-method)). It is never a function value: it converts to no function type or `Closure` and binds no `some F`, so every call of it is direct. The access ends with the call, since a raw pointer is unscoped. The place must be storage that a view could outlive: a variable, a stored field or element, or a storage projection ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)), never an access-bound projection or an under-aligned place ([04](04-types.md#packed-structs-and-under-aligned-places)), which reach the call only as a temporary the call would outlive; either is a compile error. An object's value or a thread-local qualifies, but the dynamic access the call takes ends with it, so no mark guards later uses of the address: they keep the rules on raw accesses above, and stay in bounds only while the object, or the thread's copy, lives. An under-aligned field's address is its enclosing place's plus `field.offset` ([10](10-compile-time.md#what-reflection-can-read)). Its argument, borrowed or not, is always the caller's place, never a copy ([01](01-values-and-ownership.md#parameters)).

**Raw memory.**

- `p.initialize(to: v)` moves `v` into uninitialized memory without running a `deinit` on what was there.
- `p.move()` moves the value out and leaves the memory uninitialized.
- `p.deinitialize()` destroys the value in place, running its `deinit` and its fields', and `p.deinitialize(count: n)` does so for `n` values.
- Plain assignment `p.pointee = v` assumes initialized memory and destroys the old value first, as for any place.

**Raw allocations.** `allocator.allocateRaw(bytes:align:)` returns a `RawAllocation`, a copyable record of the address, an `unsafe` field, so safe code never sees it, the size and alignment, and the **allocator word** ([06](06-memory-and-allocators.md#how-values-record-their-allocator)), or `nil` when the allocator can't make it. `reallocateRaw(_:bytes:)` resizes one, keeping its first bytes up to the smaller size, and returns the updated record, or `nil`, leaving the old allocation live and unchanged. `freeRaw(_:)` gives one back. `reallocateRaw` and `freeRaw` reach the allocator through the record's word, and are `unsafe`: their caller promises that the word names the allocator they are called on and that the allocation is still live, and uses nothing at its old address afterwards. An `unsafe` core stores the word next to its pointer, and checks it at every open, each access that reaches the storage ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)), before it reads, writes or frees there. `word.isLive` makes that check without panicking, so the core can refuse a stale buffer instead of reading reused memory.

**Hardware access.**

- `volatileLoad(p)` and `volatileStore(p, v)`, for a `T` of 1, 2, 4 or 8 bytes, are each performed exactly once, at `T`'s width, and in program order with the thread's other volatile accesses, never merged, split or removed;
- `fence(.acquire / .release / .acqRel / .seqCst)` is a memory fence of that ordering ([07](07-concurrency.md#atomics-and-locks));
- `compilerFence(_:)` orders the thread's accesses only against code interrupting that same thread, such as a signal handler.

### `@safe` modules

A module the build declares `@safe` ([10](10-compile-time.md#what-a-build-declares)) is restricted to the safe subset: every construct whose correctness the compiler takes on trust is an error anywhere in it. It can still call safe wrappers that other modules built with `unsafe`. It rejects:

- `unsafe` blocks, expressions, functions and conformances, `@pod`, `@parks`, `@export` functions, `import c` config blocks and `extern c func` declarations. The conformances, those attributes, the config blocks and those declarations are the **unverified promises**:
    - `@pod`, which states that every bit pattern of a struct or union is valid ([04](04-types.md#plain-data-pod-and-bit-casts));
    - `@export` on a function, a promise about its C name and callers ([09](09-c-interop.md#calling-rayo-from-c));
    - a conformance to an **`unsafe protocol`**, a contract the compiler can't check ([05](05-protocols-generics-and-closures.md#conformances)). The language's own are `Sendable` and `Synchronized` ([07](07-concurrency.md)), `Frozen` and `AllocatorImpl` ([06](06-memory-and-allocators.md)), and `PlainDeinit` ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)). A conformance the compiler derives itself, such as `Frozen` for a type with no interior mutability or `Sendable` for a type whose fields are all `Sendable`, is no promise;
    - a conformance written `: unsafe P` because a witness is an `unsafe` field, a union member that isn't safe to read, a static stored `var` that isn't `@threadlocal`, which also promises that its accesses never race, or an `unsafe` declaration meeting a safe requirement ([05](05-protocols-generics-and-closures.md#conformances)), or because its derived `==` or `hash(into:)` reads such a field or member ([05](05-protocols-generics-and-closures.md#equality-and-ordering));
    - a function declared `@parks`, which promises the parking-wait contract ([08](08-grace-periods-and-checkpoints.md#writing-a-parking-wait-the-parks-promise));
    - a rule in an `import c` config block, each an assertion about the header's C: `noalloc` ([09](09-c-interop.md#c-calls-in-noalloc-code-noalloc)), `stack` ([09](09-c-interop.md#the-stack-a-c-call-needs)), and `struct`, `union` or `enum S in "h"` ([09](09-c-interop.md#importing-headers)). A `parks` rule is no promise, since each call's `unsafe` code vouches for what the call uses ([09](09-c-interop.md#blocking-c-calls-parks)), and neither is a `stack` in a `@c` function pointer type, since a function converts to the type only when the type declares at least the function's need;
    - an `extern c func` declaration, an assertion about its module's `extern c` code or a linked library ([09](09-c-interop.md#inline-c));
- `unchecked` blocks ([below](#check-levels));
- `extern c` blocks of C code ([09](09-c-interop.md#inline-c)).

## Check levels

```swift
let v = verts[i]          // bounds check: without it, a bad index would read memory outside the buffer
let n = a + b             // overflow check: without it, the sum wraps, which is a wrong value but memory-safe
```

**Checks come in two classes:**

- **Memory-safety checks**, bounds checks among them, make safe code sound. They are **on in every build**, and only `unchecked` code can strip them ([below](#choosing-checks-for-a-module-or-a-scope)).
- **Diagnostic checks** catch logic bugs whose failure is still memory-safe, such as wrapping arithmetic.

**Each diagnostic check is on or off where code is written**, by the innermost of an enclosing `@checks`, the module's settings and the profile default, and an enclosing `unchecked` block turns every one off (below). `target.checks` holds those that are on ([10](10-compile-time.md#static-if-and-conditional-compilation)).

### Choosing checks for a module or a scope

```swift
@checks(.all) func accumulate(_ total: mutable Int, _ xs: Span<Int>) { … }   // overflow checked here, even in ship
@checks(.none) do { for x in xs { sum += x } }                            // diagnostics off in this block only; bounds stay on

unchecked {                        // bounds and the table's other checks off here
    for i in 0..<n { dst[i] = src[i] * k }
}
```

**Diagnostic checks can be chosen per module and per scope.**

- **Per scope**, for a function, a type's members or a `do` block: `@checks(…)`, which takes `.all`, `.none`, or a set of the diagnostic checks in the table below, `.overflow` and `.assert`, as in `@checks([.overflow])`, and sets exactly those on for its scope, replacing what encloses it.
- **Per module**, with the same values, in the build's settings ([10](10-compile-time.md#what-a-build-declares)).
- **In `@safe` modules too**, since they only choose diagnostic checks.

**What `unchecked` removes.** An `unchecked` block removes every check in the table below that the code written inside it performs, and those of the `@inline` functions it calls, whose bodies become part of it ([12](12-compilation-model.md#functions-that-are-never-calls-inline)), such as a collection's subscript. It removes none of the other functions it calls, and none of the panics [above](#what-panics) that the table doesn't list. A diagnostic check it removes acts as where it is off: an overflow wraps or truncates, and `assert` doesn't evaluate its condition. Any other removed check's failure is undefined behavior. It removes no synchronization, since a lock, an atomic operation and a section entry are the operation itself, and a check that also orders memory, as a single-sided queue's side check does ([07](07-concurrency.md#queues-and-channels)), keeps that ordering when its failure test is removed.

### The checks

| Check | Class | `dev` | `profile` | `ship` |
| --- | --- | --- | --- | --- |
| Indexing and slicing bounds, and string ranges on Unicode scalar boundaries | memory safety | on | on | on |
| Stack space, on entry to each function and before each call into C | memory safety | on | on | on |
| Thread-bound object: liveness and conflicting accesses | memory safety | on | on | on |
| Thread-local: initialized, not destroyed, and conflicting accesses | memory safety | on | on | on |
| Opening an owning value whose storage a reset or an unregistration invalidated | memory safety | on | on | on |
| Safety counts: reader, pin and owner counts | memory safety | on | on | on |
| `Slice` of a locked blob or `List`: current length and alignment, or current count | memory safety | on | on | on |
| Taking a `Mutex`'s or an `RwLock`'s exclusive access on a thread that holds either kind, or either kind on a thread that holds the exclusive one | memory safety | on | on | on |
| Single-producer and single-consumer queues: overlapping calls on one side | memory safety | on | on | on |
| Reading a global before its initializer has run | memory safety | on | on | on |
| Entry from C before startup or after shutdown | memory safety | on | on | on |
| Polling a finished task | memory safety | on | on | on |
| Integer division and remainder by zero, and float-to-integer conversion of NaN or an out-of-range value | memory safety | on | on | on |
| Integer overflow on `+ - *`, unary `-`, `Int.min / -1`, unlabeled integer conversions whose value doesn't fit, and imported bitfield writes that don't fit the width ([09](09-c-interop.md#structs-unions-and-enums)) | diagnostic | on | on | off: wraps or truncates ([04](04-types.md#integer-overflow-division-and-shifts)) |
| `x!` on `nil`, and `try!` on an error | memory safety | on | on | on |
| `precondition` | memory safety | on | on | on |
| `unreachable()` reached | memory safety | on | on | on |
| `assert` | diagnostic | on | off | off |

Division by zero, the float-to-integer conversions, `!`, `try!` and `unreachable()` count as memory safety since, unchecked, they are undefined behavior, and `precondition` does since `unsafe` code may rely on it.

## Build profiles

The profiles, `dev`, `profile` and `ship`, are a closed set, with the diagnostic checks the table above gives each. A build that names none uses `ship`.
