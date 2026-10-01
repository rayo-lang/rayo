# Rayo

Rayo is a systems programming language with the control of C++ and memory safety without a garbage collector. This glossary names the spec's terms, says in one sentence what each is, and links to the section that defines it. The rules live in the chapters.

## Language

### Ownership and borrowing

**Borrow**:
Use of a value by code that doesn't own it: a **shared** borrow only reads it, and a **mutable** borrow may change it ([01](docs/spec/01-values-and-ownership.md)).
_Avoid_: loan

**Changeable place**:
A place that may be changed or lent with `&`, such as a `var` that owns its value, a temporary or a `mutable` parameter ([01](docs/spec/01-values-and-ownership.md#bindings)).

**Consume**:
To move a value out of a place the code owns, implicitly or with `consume place` ([01](docs/spec/01-values-and-ownership.md#moving-values-out)).

**Copy**:
A second value with the same contents: `copy x` duplicates a copyable value's bytes, and `x.clone()` a move-only value's storage ([01](docs/spec/01-values-and-ownership.md#copies)).

**Copyable**:
A type whose values `copy` duplicates byte for byte, without allocating ([01](docs/spec/01-values-and-ownership.md#copies)).
_Avoid_: trivially copyable, bitwise-copyable

**Hidden local**:
A local the language declares to keep a value that a statement can't name, such as a `when` subject or a loop's sequence ([01](docs/spec/01-values-and-ownership.md#destruction)).

**Law of exclusivity**:
The rule that nothing else reaches a place while it is mutably borrowed, and nothing changes it while it is borrowed shared ([01](docs/spec/01-values-and-ownership.md#the-law-of-exclusivity)).
_Avoid_: aliasing XOR mutability

**Maybe-initialized**:
Said of a place that holds a value on only some of the paths that reach a point, so it can't be used until it is assigned ([01](docs/spec/01-values-and-ownership.md#moving-values-out)).
_Avoid_: conditionally initialized

**Move**:
Taking a value from a place, which hands it to a new owner and leaves the place without a value until it is assigned again ([01](docs/spec/01-values-and-ownership.md#moves)).
_Avoid_: transfer, destructive copy

**Move-only**:
A type whose values are moved, or copied only with a named call such as `clone()`, never with `copy` ([01](docs/spec/01-values-and-ownership.md#copies)).
_Avoid_: non-copyable, linear, affine

**Overlap**:
Two places overlap when one contains the other, when they may be the same place, as `a[i]` and `a[j]` may, or when they share bytes, as a union's members do ([01](docs/spec/01-values-and-ownership.md#which-places-overlap)).

**Owner**:
The place or value that holds a value and decides when it is destroyed; a value has one owner, unless it is reference-counted ([01](docs/spec/01-values-and-ownership.md)).
_Avoid_: holder

**Place**:
Storage that holds a value: a local, a global, a parameter or a temporary, or a part of one, such as `enemy.hp` or `list[i]` ([01](docs/spec/01-values-and-ownership.md)).
_Avoid_: lvalue

**Safe code**:
All code outside `unsafe` code, `unchecked` blocks and C, which has no undefined behavior ([01](docs/spec/01-values-and-ownership.md#tiers-of-checking)).
_Avoid_: checked code

**Tier**:
One of the three levels at which a pattern is checked: **static**, by the compiler at no run-time cost; **dynamic**, at each use; and **unsafe**, not at all ([01](docs/spec/01-values-and-ownership.md#tiers-of-checking)).
_Avoid_: safety level, mode

### Views and dependencies

**Absorption**:
The rule that after a call, each scoped `mutable` argument takes on what the call's other arguments borrow ([02](docs/spec/02-views-and-dependencies.md#dependencies)).

**Access-bound projection**:
A projection whose accessor stays suspended at its `yield` until nothing uses what it yielded, since it may yield a temporary; a projection is access-bound unless declared otherwise ([02](docs/spec/02-views-and-dependencies.md#projections-read-and-modify-accessors)).

**Dependency set**:
The places and dynamic accesses a scoped value borrows from, each shared or exclusive; it is what the value **carries** ([02](docs/spec/02-views-and-dependencies.md#dependencies)).
_Avoid_: lifetime, region, loan set

**Dynamic access**:
An access to an object, a `Slice`'s buffer or a thread-local, checked at run time and held until nothing that depends on it is used ([02](docs/spec/02-views-and-dependencies.md#dependencies)).

**Full statement**:
A statement, or a condition or subject that counts as a statement of its own, whose end destroys the temporaries it made ([02](docs/spec/02-views-and-dependencies.md#dependencies)).
_Avoid_: full-expression

**Guard type**:
A type declared `@guard`, whose values hold a lock for as long as they live, as `MutexGuard` does ([02](docs/spec/02-views-and-dependencies.md#lock-guards-are-released-on-the-thread-that-took-them)).
_Avoid_: lock token

**Mutable view**:
A view through which what it views can be changed, such as a `MutableSpan`, a lock guard or a `mutating` function value ([02](docs/spec/02-views-and-dependencies.md#dependencies)).
_Avoid_: exclusive reference

**Optional projection**:
A projection whose declared type is written `T?`, which yields either a place of type `T` or `nil` ([02](docs/spec/02-views-and-dependencies.md#projections-read-and-modify-accessors)).

**PlainDeinit**:
A type whose `deinit` only destroys what it owns alone and frees its own buffers, so destroying it uses no more than destroying its parts does ([02](docs/spec/02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)).

**Projection**:
An accessor that yields a place instead of returning a value: a `read` or a `modify` ([02](docs/spec/02-views-and-dependencies.md#projections-read-and-modify-accessors)).

**Scoped value**:
A value of a type that conforms to `Scoped`, which stays within the scope that lent it; every view whose memory could be freed while it reads it is one ([02](docs/spec/02-views-and-dependencies.md#scoped-values)).
_Avoid_: non-escaping value, lifetime-bound value

**Sealed type**:
A concrete type that holds, at any depth, no function value, closure, `any P`, `some P`, interpolated literal, type parameter or associated type; every other type is **unsealed** ([02](docs/spec/02-views-and-dependencies.md#dependencies)).

**Shallow type**:
A copyable type that holds no inline array at any depth ([02](docs/spec/02-views-and-dependencies.md#dependencies)).

**Static storage**:
Global `let`s and `const`s, and the views their `Synchronized` values lend, which any function may return a view of ([02](docs/spec/02-views-and-dependencies.md#dependencies)).

**Storage projection**:
A projection declared with a `yield` item, such as `where yield borrows self`, which yields part of the storage the item names ([02](docs/spec/02-views-and-dependencies.md#projections-read-and-modify-accessors)).

**View**:
A value that borrows memory something else owns, such as a `Span` or a `StringView` ([02](docs/spec/02-views-and-dependencies.md#scoped-values)).
_Avoid_: reference (as a noun), pointer (raw, object and reference-counted pointers are other things)

### Handles and objects

**Generation**:
A count that a handle, a weak pointer or a weak link holds to name the element, object or `Shared` value it was made for, so it never names a later one ([03](docs/spec/03-handles-and-objects.md#destroying-an-object)).
_Avoid_: version, epoch

**Handle**:
A small, copyable index into a pool, checked at each use, which reads `nil` once its element is removed ([03](docs/spec/03-handles-and-objects.md#pools-and-handles)).
_Avoid_: entity ID

**Home thread**:
The thread that made an object; the object is **thread-bound** to it, and is used and destroyed only there ([03](docs/spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)).
_Avoid_: owner thread

**Object**:
The value a `UniquePointer` owns, which any number of weak pointers can point at, and which is checked at each access ([03](docs/spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)).
_Avoid_: class instance, heap object, entity

**Pin**:
A `Pin<T>` or a `LocalPin<T>`, which keeps a `StablePool` element or an object at its address, for C, for as long as it lives ([03](docs/spec/03-handles-and-objects.md#pinning-for-c)).

**Read access, modify access**:
An access to an object's value that holds a shared mark (a read) or an exclusive mark (a modify) until nothing that depends on it is used ([03](docs/spec/03-handles-and-objects.md#dynamic-exclusivity)).

**Stale**:
Said of a handle whose element was removed ([03](docs/spec/03-handles-and-objects.md#pools-and-handles)), or of a value whose storage a reset or an unregistration invalidated ([06](docs/spec/06-memory-and-allocators.md#what-a-reset-does)); using one reads `nil` or panics, and never reaches freed memory.
_Avoid_: dangling (what a stale link never is), expired

**Weak pointer**:
A copyable `WeakPointer<T>` to an object, which reads `nil` once the object is destroyed ([03](docs/spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)).
_Avoid_: weak reference, weak link (a `WeakShared`)

### Types

**Niche**:
A bit pattern a type never uses, in which an optional of it stores `nil` at no extra size ([04](docs/spec/04-types.md#optionals)).

**Padding-free**:
Said of a type with no padding bytes, as `T.isPaddingFree` reports ([04](docs/spec/04-types.md#plain-data-pod-and-bit-casts)).

**Pod**:
A type for which any bytes make a valid value, so bytes from a file or a packet can be read as one ([04](docs/spec/04-types.md#plain-data-pod-and-bit-casts)).
_Avoid_: trivial type

**Primary initializer**:
A struct's header, which lists its stored fields once and is also its initializer ([04](docs/spec/04-types.md#structs)).
_Avoid_: memberwise initializer

**Row**:
A view of one index of an `SoA<T>` across every column, with one projection per field of `T` ([04](docs/spec/04-types.md#struct-of-arrays-soat)).

**Unconditional extension**:
An extension that gives none of its type's generic arguments and has no `where` clause ([04](docs/spec/04-types.md#initializers)).

**Under-aligned**:
Said of a place guaranteed less than its type's alignment, such as a field of a packed struct, which code uses only by value ([04](docs/spec/04-types.md#packed-structs-and-under-aligned-places)).
_Avoid_: misaligned (a misaligned access is undefined behavior)

### Protocols, generics and closures

**Closure kind**:
Whether a function type only reads its captures, changes them (`mutating`) or consumes them (`consuming`) ([05](docs/spec/05-protocols-generics-and-closures.md#closure-kinds)).

**Compile-time code**:
Code the compiler checks at each instantiation instead of once, such as `static if` branches, `static for` bodies, `const` expressions and reflection on a type parameter ([05](docs/spec/05-protocols-generics-and-closures.md#protocols-and-generics)).

**Default**:
A member of a protocol extension that matches a requirement, and is the witness of every conformance that declares none ([05](docs/spec/05-protocols-generics-and-closures.md#protocols-and-generics)).

**Existential**:
A value of type `any P` or `mutable any P`, or held in an unscoped form such as `Box<any P>`, whose concrete type is known only at run time ([05](docs/spec/05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).
_Avoid_: trait object, protocol type, boxed protocol

**Function value**:
A value of a function type, which views a closure's storage or names a function ([05](docs/spec/05-protocols-generics-and-closures.md#function-typed-values)).
_Avoid_: function pointer (a `@c` type)

**Marker protocol**:
A protocol with no requirements that states a property of a type, such as `Copyable`, `Scoped` or `Sendable`; the compiler derives some, such as `Copyable` and `Sendable`, from what a type holds ([05](docs/spec/05-protocols-generics-and-closures.md#conformances)).
_Avoid_: marker trait, tag protocol

**Unscoped closure**:
A `Closure<F>`, which owns its captures, and so may outlive the scope that made it ([05](docs/spec/05-protocols-generics-and-closures.md#unscoped-closures-closuref)).
_Avoid_: escaping closure, boxed closure

**Witness**:
The member, or for an associated type the type, that meets one requirement of a protocol in a conformance ([05](docs/spec/05-protocols-generics-and-closures.md#conformances)).

### Memory and allocators

**Allocator**:
A copyable id that names a registered allocator implementation ([06](docs/spec/06-memory-and-allocators.md#allocator-values)).
_Avoid_: allocator handle, allocator reference

**Allocator word**:
The 8 bytes in which an owning value records the allocator its storage came from, dated against that allocator's resets ([06](docs/spec/06-memory-and-allocators.md#how-values-record-their-allocator)).

**Arena**:
An allocator that frees nothing individually, and frees everything it handed out at once when it is reset ([06](docs/spec/06-memory-and-allocators.md#allocator-values)).
_Avoid_: region, zone, bump allocator

**Backing**:
The allocator another allocator draws its memory from, such as the one a wrapper wraps ([06](docs/spec/06-memory-and-allocators.md#allocator-values)).
_Avoid_: parent allocator, upstream

**Current allocator**:
The allocator, kept per thread, that constructors record when they aren't given one, and that `using allocator` sets for a block ([06](docs/spec/06-memory-and-allocators.md#the-current-allocator)).
_Avoid_: default allocator, context allocator

**Frozen**:
A type with no interior mutability: nothing writes its values, or what they own, through a shared borrow ([06](docs/spec/06-memory-and-allocators.md#frozen-types-with-no-interior-mutability)).

**Heap**:
An allocator that frees each allocation individually, such as `.system` ([06](docs/spec/06-memory-and-allocators.md#allocator-values)).

**Open**:
An access that reaches the storage an owning value owns, which checks that the storage isn't stale ([06](docs/spec/06-memory-and-allocators.md#opening-an-owning-value-checks-it)).

**Owning value**:
A value that owns storage from an allocator, such as a `List`, a `String` or a `Box` ([06](docs/spec/06-memory-and-allocators.md#opening-an-owning-value-checks-it)).
_Avoid_: container (for the general case), heap value

**Reference counting**:
Sharing one **reference-counted value** among several owners, each a **reference-counted pointer**, `Shared<T>` or `LocalShared<T>`; dropping the last one destroys the value ([06](docs/spec/06-memory-and-allocators.md#sharedt-data-with-many-owners)).
_Avoid_: counted owner, counted value, ARC

**Reset**:
The arena operation that frees everything the arena handed out at once, after checking that nothing uses it ([06](docs/spec/06-memory-and-allocators.md#what-a-reset-does)).
_Avoid_: rewind

**Slice**:
A `Slice<T>`: a checked, copyable view into a buffer behind a `Shared`, which can be stored anywhere and reads `nil` once the buffer is gone ([06](docs/spec/06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)).
_Avoid_: span (a `Span` is scoped)

**Stamp**:
An ordered token the runtime gives each block an arena hands out memory from, which names the arena and dates the block against its resets ([06](docs/spec/06-memory-and-allocators.md#what-a-reset-does)).
_Avoid_: epoch, generation (a handle's)

**Static allocator**:
The allocator of the values in static data, which never allocates or frees at run time ([06](docs/spec/06-memory-and-allocators.md#the-static-allocator)).

**Static data**:
The memory that holds `const`s and the global `let`s evaluated at compile time, which nothing writes or frees ([06](docs/spec/06-memory-and-allocators.md#the-static-allocator)).

**TrivialFree**:
A type whose destruction does nothing but free memory ([06](docs/spec/06-memory-and-allocators.md#releasing-a-value-without-destroying-it-trivialfree)).

**Unregistering**:
Ending an allocator with `Allocator.unregister`: its values go stale, its objects are destroyed, and then its implementation is ([06](docs/spec/06-memory-and-allocators.md#unregistering-an-allocator)).

**Weak link**:
A copyable `WeakShared<T>`, which names a reference-counted value without keeping it alive ([06](docs/spec/06-memory-and-allocators.md#sharedt-data-with-many-owners)).
_Avoid_: weak reference, weak pointer (an object's)

**Wrapper**:
An allocator that passes another allocator's allocations through and keeps accounts of them, such as a budget ([06](docs/spec/06-memory-and-allocators.md#allocator-values)).
_Avoid_: decorator, proxy allocator

### Concurrency

**Awaitable**:
A value a task polls at each step until it reports that it is done ([07](docs/spec/07-concurrency.md#awaitables)).
_Avoid_: future (a `Future` is one awaitable)

**Lent work**:
Function values that borrow the caller's data, which a library runs on its threads and finishes before those borrows can end ([07](docs/spec/07-concurrency.md#lending-work-to-other-threads)).

**Nested entry**:
An entry into Rayo from C on a thread that already has a Rayo frame below it ([07](docs/spec/07-concurrency.md#initialization-at-startup)).

**Resume parameter**:
The one parameter a task's owner passes in at every step ([07](docs/spec/07-concurrency.md#semantics)).

**Sendable**:
A type whose values may be used from another thread: moved there, or borrowed there until the lending call returns ([07](docs/spec/07-concurrency.md#what-may-cross-threads-sendable)).

**Startup**:
The run of global initializers, one module at a time, before `main`, or in `rayo_init()` when a C program embeds Rayo ([07](docs/spec/07-concurrency.md#initialization-at-startup)).

**Synchronized**:
A type whose non-`mutating` methods change it only through its own synchronization, such as a `Mutex` or a queue, so threads can share it ([07](docs/spec/07-concurrency.md#the-synchronized-contract)).
_Avoid_: concurrent type

**Task**:
The value a `task func` call returns: a coroutine whose size is known at compile time, which its owner steps until it finishes ([07](docs/spec/07-concurrency.md#task-functions-explicitly-stepped-coroutines)).
_Avoid_: async function, future (a `Future` is one awaitable)

**Teardown**:
The end of a thread's Rayo code, which destroys its copies of the thread-locals and its objects, on that thread ([07](docs/spec/07-concurrency.md#global-state)).

### C interop

**C entry**:
A function C can call: a `@c func`, an `@export` function, or a closure literal converted to a `@c` pointer ([08](docs/spec/08-c-interop.md#c-entries-and-threads)).

**Config block**:
The `unsafe { … }` block that may end an `import c`, holding rules about the header's C ([08](docs/spec/08-c-interop.md#importing-headers)).

**Memory location**:
A maximal run of adjacent nonzero-width C bitfields, which counts as one place for exclusivity ([08](docs/spec/08-c-interop.md#structs-unions-and-enums)).

**Open enum**:
An imported C enum, which may hold any value of its underlying type unless its header declares it closed ([08](docs/spec/08-c-interop.md#structs-unions-and-enums)).

### Compile time

**Freezable**:
Said of a value that can be frozen: copied into read-only data, where it stays unchanged for the whole run, as a `const` that reaches run time must be ([09](docs/spec/09-compile-time.md#consts-that-reach-run-time)).

**Immortal data**:
Read-only bytes that nothing writes or frees, such as a literal's, which a `StaticSpan` or a `StaticString` views ([09](docs/spec/09-compile-time.md#staticspan-views-of-immortal-data)).

**Reaches run time**:
Said of a `const` named anywhere but in a `const` initializer, a `static if` or `static for` condition or list, or an attribute argument; the compiler copies it into read-only data ([09](docs/spec/09-compile-time.md#consts-that-reach-run-time)).

**Static closure**:
A closure whose body is instantiated once per field, as the argument of `T.construct` or `T.makeCase` ([09](docs/spec/09-compile-time.md#constructing-values-reflectively)).

### Errors and safety

**Build profile**:
One of `dev`, `profile` and `ship`, each with its own default set of diagnostic checks ([10](docs/spec/10-errors-and-safety.md#build-profiles)).
_Avoid_: configuration, build mode

**Diagnostic check**:
A run-time check that catches a logic bug whose failure is still memory-safe, such as integer overflow; `@checks`, a module's settings and the build profile turn each one on or off ([10](docs/spec/10-errors-and-safety.md#check-levels)).
_Avoid_: debug check

**Error union**:
A tagged union with one member per error type, written `(IoError | ParseError)`, as in `throws(IoError | ParseError)` ([10](docs/spec/10-errors-and-safety.md#error-unions)).

**Memory-safety check**:
A run-time check, such as a bounds check, that keeps safe code sound; it is on in every build ([10](docs/spec/10-errors-and-safety.md#check-levels)).
_Avoid_: safety check

**Panic**:
How a bug, such as unwrapping `nil` with `!`, stops the program: reported through the platform, it never returns ([10](docs/spec/10-errors-and-safety.md#panics)).
_Avoid_: crash, abort, exception

**Recoverable error**:
A typed value, such as a missing file, that a function throws and its caller must handle ([10](docs/spec/10-errors-and-safety.md)).
_Avoid_: exception

**Unsafe code**:
Code that uses an operation needing `unsafe`, such as dereferencing a raw pointer or calling C, whose soundness the code promises instead of the compiler ([10](docs/spec/10-errors-and-safety.md#unsafe-code)).

**Unsafe protocol**:
A protocol, such as `Sendable` or `Frozen`, whose declared conformance is a contract the compiler can't check ([10](docs/spec/10-errors-and-safety.md#safe-modules)).

**Unverified promise**:
A declaration the compiler takes on trust, such as an `unsafe` conformance, an `@export` function or an `import c` config block ([10](docs/spec/10-errors-and-safety.md#safe-modules)).

### Compilation

**Prelude**:
The std declarations every module sees without an import ([11](docs/spec/11-compilation-model.md#modules-and-names)).
