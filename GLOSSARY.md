# Rayo

Rayo is a systems programming language with the control of C++ and memory safety without a garbage collector. This glossary names the spec's terms, says in one sentence what each is, and links to the section that defines it. The rules live in the chapters.

## Language

### Ownership and borrowing

**Argument label**:
The name a call writes before an argument, as `by` in `damage(&boss, by: 10)` ([01](docs/spec/01-values-and-ownership/parameters.md#argument-labels)).

**Borrow**:
Use of a value by code that doesn't own it: a **shared** borrow only reads it, and a **mutable** borrow may change it ([01](docs/spec/01-values-and-ownership.md)).
_Avoid_: loan

**Borrowing binding**:
A binding that names a place it borrows: a declaration written with `borrow` or `&` on a place, or a condition's or pattern's binding of a place ([01](docs/spec/01-values-and-ownership/bindings.md#bindings)).
_Avoid_: reference variable, alias

**Changeable place**:
A place that may be changed or lent with `&`, such as a `var` that owns its value, a temporary or a `mutable` parameter ([01](docs/spec/01-values-and-ownership/bindings.md#changeable-places)).

**Consume**:
To move a value out of a place the code owns, implicitly or with `consume place` ([01](docs/spec/01-values-and-ownership/moving-values-out.md#moving-values-out)).

**Copy**:
A second value with the same contents: `copy x` duplicates a copyable value's bytes, and `alloc x.clone()` a move-only value's storage ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#copies)).

**Copyable**:
A type whose values `copy` duplicates byte for byte, without allocating ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#copyable-types)).
_Avoid_: trivially copyable, bitwise-copyable

**Hidden local**:
A local the language declares to keep a value that a statement can't name, such as a `when` subject or a loop's sequence ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#destruction)).

**Law of exclusivity**:
The rule that nothing else reaches a place while it is mutably borrowed, and nothing changes it while it is borrowed shared ([01](docs/spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).
_Avoid_: aliasing XOR mutability

**Maybe-initialized**:
Said of a place that holds a value on only some of the paths that reach a point, so it can't be used until it is assigned ([01](docs/spec/01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)).
_Avoid_: conditionally initialized

**Move**:
Taking a value from a place, which hands it to a new owner and leaves the place without a value until it is assigned again ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#moves)).
_Avoid_: transfer, destructive copy

**Move-only**:
A type whose values are moved, or copied only with a named call such as `clone()`, never with `copy` ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#copyable-types)).
_Avoid_: non-copyable, linear, affine

**Overlap**:
Two places overlap when one contains the other, when they may be the same place, as `a[i]` and `a[j]` may, or when they share bytes, as a union's members do ([01](docs/spec/01-values-and-ownership/exclusivity.md#which-places-overlap)).

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
The rule that after a call, each scoped `mutable` argument takes on what the call's other arguments borrow ([02](docs/spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)).

**Dependency set**:
The places and dynamic accesses a scoped value borrows from, each shared or exclusive; it is what the value **carries** ([02](docs/spec/02-views-and-dependencies.md#dependencies)).
_Avoid_: lifetime, region, loan set

**Dynamic access**:
An access to an object, a `Slice`'s buffer or a thread-local, checked at run time and held until nothing that depends on it is used ([02](docs/spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)).

**Full statement**:
A statement, or a condition or subject that counts as a statement of its own, whose end destroys the temporaries it made ([02](docs/spec/02-views-and-dependencies/dependency-projection-and-results.md#temporaries)).
_Avoid_: full-expression

**Guard type**:
A type declared `@guard`, whose values hold a lock for as long as they live, as `MutexGuard` does ([02](docs/spec/02-views-and-dependencies/dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)).
_Avoid_: lock token

**Mutable view**:
A view through which what it views can be changed, such as a `MutableSpan`, a lock guard or a `mutating` function value ([02](docs/spec/02-views-and-dependencies/dependency-projection-and-results.md#mutable-views)).
_Avoid_: exclusive reference

**Optional place property**:
A place property whose declared type is written `T?`, which hands out either a place of type `T` or `nil` ([02](docs/spec/02-views-and-dependencies/place-and-value-properties.md#optional-places-and-tuples-of-places)).

**Place property**:
A computed property or subscript whose `borrow`, and optional `mutate`, hand out a place in storage, which code uses as it would a stored field, with no accessor code after ([02](docs/spec/02-views-and-dependencies/place-and-value-properties.md#place-and-value-properties)).
_Avoid_: projection, `read`/`modify` accessor

**PlainDeinit**:
A type whose `deinit` only destroys what it owns alone and frees its own buffers, so destroying it uses no more than destroying its parts does ([02](docs/spec/02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)).

**Scoped value**:
A value of a type that conforms to `Scoped` and must stay within its scope. A view into memory that can be freed is scoped; a scoped value need not be a view ([02](docs/spec/02-views-and-dependencies/scoped-values.md#scoped-values)).
_Avoid_: non-escaping value, lifetime-bound value

**Sealed type**:
A concrete type that holds, at any depth, no function value, closure, `any P`, `some P`, interpolated literal, type parameter or associated type; every other type is **unsealed** ([02](docs/spec/02-views-and-dependencies/dependency-projection-and-results.md#closure-calls)).

**Shallow type**:
A copyable type that holds no inline array at any depth ([02](docs/spec/02-views-and-dependencies/dependency-projection-and-results.md#shallow-values)).

**Source**:
A place, or what a place borrows, that a place property's place may lie in: `self` by default, or what its `where return` items name ([02](docs/spec/02-views-and-dependencies/place-and-value-properties.md#the-place-lies-in-its-sources)).

**Static storage**:
Global `let`s and `const`s, and the views their `Synchronized` values lend, which any function may return a view of ([02](docs/spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)).

**Value property**:
A computed property or subscript whose `get` returns a value and whose optional `set` takes one back, so a change works on a copy that `set` writes back ([02](docs/spec/02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)).

**View**:
A value that borrows memory something else owns, such as a `Span` or a `StringView` ([02](docs/spec/02-views-and-dependencies/scoped-values.md#scoped-values)).
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
Said of a handle whose element was removed ([03](docs/spec/03-handles-and-objects.md#pools-and-handles)), or of a value whose storage a reset or an unregistration invalidated ([06](docs/spec/06-memory-and-allocators/arena-safety.md#what-a-reset-does)). Using one reads `nil` or panics, and never reaches freed memory.
_Avoid_: dangling (what a stale link never is), expired

**Weak pointer**:
A copyable `WeakPointer<T>` to an object, which reads `nil` once the object is destroyed ([03](docs/spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)).
_Avoid_: weak reference, weak link (a `WeakShared`)

### Types

**Hashing type**:
A type conforming to `Hashing`, such as the default `SeededHashing` or `FixedHashing`, whose value a `Map` or `Set` keeps to make the `Hasher` that each key is fed to ([04](docs/spec/04-types/collections.md#hash-maps-and-sets)).
_Avoid_: BuildHasher, hasher builder

**Layout order**:
The order of a struct's fields in memory: by decreasing alignment, with declaration order among equals, or declaration order for a `@c` or `@packed` struct ([04](docs/spec/04-types/structs.md#structs)).

**Mask**:
Any `Simd<Bool, N>`, such as a comparison of vectors gives, which `select` uses and which has `any`, `all` and its lanes as `UInt64` `bits` ([04](docs/spec/04-types/numbers-and-math.md#masks)).

**Name**:
std's interned text: a pointer-sized value that equals another exactly when their texts are equal, and whose text lives for the rest of the program ([04](docs/spec/04-types/collections.md#collections-and-strings)).
_Avoid_: hashed name, string hash, string id

**Narrowing**:
Treating an optional place as its payload's type after a check that it isn't `nil`, for as long as nothing can make it `nil` ([04](docs/spec/04-types/enums.md#narrowing)).
_Avoid_: smart cast, flow typing

**Niche**:
A bit pattern a type never uses, in which an optional of it stores `nil` at no extra size ([04](docs/spec/04-types/enums.md#optionals)).

**Padding-free**:
Said of a type with no padding bytes, as `T.isPaddingFree` reports ([04](docs/spec/04-types/data-layout.md#plain-data-pod-and-bit-casts)).

**Pod**:
A type for which any bytes make a valid value, so bytes from a file or a packet can be read as one ([04](docs/spec/04-types/data-layout.md#plain-data-pod-and-bit-casts)).
_Avoid_: trivial type

**Primary initializer**:
A struct's header, which lists its stored fields once and is also its initializer ([04](docs/spec/04-types/structs.md#structs)).
_Avoid_: memberwise initializer

**Process seed**:
The random value that startup draws from the platform once per run, from which each `SeededHashing` map derives a seed of its own, so nobody outside the program can choose colliding keys ([04](docs/spec/04-types/collections.md#hash-maps-and-sets)).
_Avoid_: random state, hash key

**Reduction**:
An operation that combines a vector's lanes into one value, such as `sum()` or a mask's `any`, in an order fixed on every target ([04](docs/spec/04-types/numbers-and-math.md#reductions)).
_Avoid_: horizontal operation

**Row**:
A view of one index of an `SoA<T>` across every column, with one place property per field of `T` ([04](docs/spec/04-types/data-layout.md#struct-of-arrays-soat)).

**Shuffle**:
An operation that builds a vector from lanes of one or two vectors, picked by a list of lane indices known at compile time, as `shuffle(v, [3, 2, 1, 0])` does ([04](docs/spec/04-types/numbers-and-math.md#shuffles-and-swizzles)).
_Avoid_: permute

**SimdLane**:
The prelude's marker protocol for the types a vector's lanes may hold, the number types and `Bool`, which no other type can declare ([04](docs/spec/04-types/numbers-and-math.md#simd-and-math)).
_Avoid_: SimdElement

**Swizzle**:
A vector property whose name lists up to four of the lanes `x`, `y`, `z` and `w`, as `v.zyx` does: a swizzle of 2 to 4 lanes is shorthand for a shuffle, and one lane is `v[i]` ([04](docs/spec/04-types/numbers-and-math.md#shuffles-and-swizzles)).

**Unconditional extension**:
An extension that gives none of its type's generic arguments and has no `where` clause ([04](docs/spec/04-types/structs.md#initializers)).

**Under-aligned**:
Said of a place guaranteed less than its type's alignment, such as a field of a packed struct, which code uses only by value ([04](docs/spec/04-types/structs.md#packed-structs-and-under-aligned-places)).
_Avoid_: misaligned (a misaligned access is undefined behavior)

### Protocols, generics and closures

**Closure kind**:
Whether a function type only reads its captures, changes them (`mutating`) or consumes them (`consuming`) ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)).

**Compile-time code**:
The parts of generic code the compiler checks at each instantiation instead of once: `static if` branches, `static for` bodies and static closures, `const` expressions and reflection on a type parameter, members generated from generic parameters, and computed names ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)).

**Default**:
A member of a protocol extension that matches a requirement, and is the witness of every conformance that declares none ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#protocol-extensions)).

**Default type argument**:
The type a struct's, enum's or union's type parameter names after `=`, which a written type that leaves that argument out takes, as `Map<Name, Int>` takes `SeededHashing` for its `H` ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#default-type-arguments)).
_Avoid_: default generic parameter

**Existential**:
A value of type `any P` or `mutable any P`, or held in an unscoped form such as `Box<any P>`, whose concrete type is known only at run time ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).
_Avoid_: trait object, protocol type, boxed protocol

**Function value**:
A value of a function type, which views a closure's storage or names a function ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)).
_Avoid_: function pointer (a `@c` type)

**Marker protocol**:
A protocol with no requirements that states a property of a type, such as `Copyable`, `Scoped` or `Sendable`; the compiler derives some, such as `Copyable` and `Sendable`, from what a type holds ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#conformances)).
_Avoid_: marker trait, tag protocol

**Type value**:
`T.self`, a value of type `Type<T>` that names the type `T`, so a function can take a type as an argument ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#value-parameters-and-type-values)).
_Avoid_: metatype

**Unscoped closure**:
A `Closure<F>`, which owns its captures, and so may outlive the scope that made it ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).
_Avoid_: escaping closure, boxed closure

**Value parameter**:
A generic parameter declared `let`, which takes a `const` value of an integer type, `Bool` or an enum without payloads, as `N` does in `Simd<T, N>` ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#value-parameters-and-type-values)).
_Avoid_: const generic

**Witness**:
The member, or for an associated type the type, that meets one requirement of a protocol in a conformance ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#conformances)).

### Memory and allocators

**`alloc`**:
The keyword that marks every construction giving a value heap storage, with an allocator it names, as in `a.alloc`, or the ambient one ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#allocating-with-alloc)).

**`alloc func`**:
A function that makes a new value for its caller, of any type, and receives that value's allocator from the `alloc` at its call, as `clone()` does ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#functions-that-make-a-new-value-alloc-func)).

**Allocating**:
A type that lets its caller choose the allocator it is made with: making one says `alloc`, the compiler gives it an allocator of its own, `self.allocator`, and that allocator is the ambient one throughout the type's code ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#the-allocating-protocol)).

**Allocator**:
A copyable id that names a registered allocator implementation ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#allocator-values)).
_Avoid_: allocator handle, allocator reference

**AllocatorImpl**:
The `unsafe` protocol a heap's implementation conforms to, which allocates, reallocates and frees, and which `ArenaImpl` and `WrapperImpl` refine ([06](docs/spec/06-memory-and-allocators/allocator-implementations.md#writing-an-allocator-allocatorimpl)).

**Allocator word**:
The 8 bytes in which an owning value records the allocator its storage came from, dated against that allocator's resets ([06](docs/spec/06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator)).

**Ambient allocator**:
The allocator a bare `alloc` takes: the one an `alloc func` or an `Allocating` type's initializer received, the instance's inside an `Allocating` type's other methods, and `.heap` everywhere else ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#the-ambient-allocator)).
_Avoid_: current allocator, default allocator, context allocator

**Arena**:
An allocator, of a type conforming to `ArenaImpl`, that frees nothing individually, and frees everything it handed out at once when it is reset ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#allocator-values)).
_Avoid_: region, zone, bump allocator

**ArenaImpl**:
The protocol an arena's implementation conforms to, refining `AllocatorImpl` with the arena's part in a reset ([06](docs/spec/06-memory-and-allocators/allocator-implementations.md#writing-an-allocator-allocatorimpl)).

**Backing**:
The allocator another allocator draws its memory from, such as the one a wrapper wraps ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#allocator-values)).
_Avoid_: parent allocator, upstream

**Frozen**:
A type with no interior mutability: nothing writes its values, or what they own, through a shared borrow ([06](docs/spec/06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)).

**Heap**:
An allocator that frees each allocation individually, such as `.heap` ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#allocator-values)).

**Open**:
An access that reaches the storage an owning value owns, which checks that the storage isn't stale ([06](docs/spec/06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).

**Owning value**:
A value that owns storage from an allocator, such as a `List`, a `String` or a `Box` ([06](docs/spec/06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).
_Avoid_: container (for the general case), heap value

**Reference counting**:
Sharing one **reference-counted value** among several owners, each a **reference-counted pointer**, `Shared<T>` or `LocalShared<T>`; dropping the last one destroys the value ([06](docs/spec/06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)).
_Avoid_: counted owner, counted value, ARC

**Reset**:
The arena operation that frees everything the arena handed out at once, after checking that nothing uses it ([06](docs/spec/06-memory-and-allocators/arena-safety.md#what-a-reset-does)).
_Avoid_: rewind

**Slice**:
A `Slice<T>`: a checked, copyable view into a buffer behind a `Shared`, which can be stored anywhere and reads `nil` once the buffer is gone ([06](docs/spec/06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)).
_Avoid_: span (a `Span` is scoped)

**Stamp**:
An ordered token the runtime gives each block an arena hands out memory from, which names the arena and dates the block against its resets ([06](docs/spec/06-memory-and-allocators/arena-safety.md#what-a-reset-does)).
_Avoid_: epoch, generation (a handle's)

**Static allocator**:
The allocator of the values in read-only data, which never allocates or frees at run time ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#the-static-allocator)).

**Read-only data**:
The memory that holds `const`s and the global `let`s evaluated at compile time, which nothing writes or frees ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#the-static-allocator)).
_Avoid_: static data

**TrivialFree**:
A type whose destruction does nothing but free memory ([06](docs/spec/06-memory-and-allocators/allocation-lifecycle.md#releasing-a-value-without-destroying-it-trivialfree)).

**Unregistering**:
Ending an allocator with `Allocator.unregister`: its values go stale, its objects are destroyed, and then its implementation is ([06](docs/spec/06-memory-and-allocators/arena-safety.md#unregistering-an-allocator)).

**Weak link**:
A copyable `WeakShared<T>`, which names a reference-counted value without keeping it alive ([06](docs/spec/06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)).
_Avoid_: weak reference, weak pointer (an object's)

**Wrapper**:
An allocator that passes another allocator's allocations through and keeps accounts of them, such as a budget ([06](docs/spec/06-memory-and-allocators/allocator-basics.md#allocator-values)).
_Avoid_: decorator, proxy allocator

**WrapperImpl**:
The protocol a wrapper's implementation conforms to, refining `AllocatorImpl` with the hooks that tell it when the arena memory under its allocations stops existing ([06](docs/spec/06-memory-and-allocators/allocator-implementations.md#writing-an-allocator-allocatorimpl)).

### Concurrency

**Awaitable**:
A value a task polls at its steps until it reports that it is done, arranging a wake of the task each time it isn't ([07](docs/spec/07-concurrency/tasks.md#awaitables)).
_Avoid_: future (a `Future` is one awaitable)

**Channel**:
A queue shared by owned ends, any number of `Sender`s and one `Receiver`, so each side learns when the other is gone ([07](docs/spec/07-concurrency/synchronization.md#queues-and-channels)).
_Avoid_: pipe

**Detached thread**:
A thread whose `Thread` value was dropped, so it runs on by itself and nothing can join it ([07](docs/spec/07-concurrency/thread-work.md#joining-a-thread)). Not to be confused with a C thread's `rayo_thread_detach`, which tears down the thread's Rayo state ([08](docs/spec/08-c-interop/c-contract-and-embedding.md#embedding-rayo-in-a-c-program)).

**Disconnected**:
Said of a channel or a future once one side's ends are all gone, so the other side stops waiting ([07](docs/spec/07-concurrency/synchronization.md#disconnected-channels)). A channel is disconnected for receiving once every `Sender` is gone and it is empty, and for sending once its `Receiver` is gone.
_Avoid_: closed (no code closes a channel)

**Future**:
The end of a future that waits for its one value: `wait()` or `await` returns the value, or `nil` once the `Promise` is gone unfulfilled ([07](docs/spec/07-concurrency/synchronization.md#futures)).

**Lent work**:
Function values that borrow the caller's data, which a library runs on its threads and finishes before those borrows can end ([07](docs/spec/07-concurrency/thread-work.md#lending-work-to-other-threads)).

**Nested entry**:
An entry into Rayo from C on a thread that already has a Rayo frame below it ([07](docs/spec/07-concurrency/global-state.md#initialization-at-startup)).

**Promise**:
The end of a future that its producer fulfills once with the value, which `fulfill` consumes ([07](docs/spec/07-concurrency/synchronization.md#futures)).
_Avoid_: promise (in plain text; the library's promise is a different guarantee)

**Resume parameter**:
The one parameter a task's owner passes in at every step ([07](docs/spec/07-concurrency/tasks.md#semantics)).

**Runner**:
What polls a task and makes its `Waker`s, such as std's `TaskSet` and `block(on:)` ([07](docs/spec/07-concurrency/tasks.md#running-tasks)).
_Avoid_: executor, scheduler

**Sendable**:
A type whose values may be used from another thread: moved there, or borrowed there until the lending call returns ([07](docs/spec/07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).

**Startup**:
The run of global initializers, one module at a time, before `main`, or in `rayo_init()` when a C program embeds Rayo ([07](docs/spec/07-concurrency/global-state.md#initialization-at-startup)).

**Step**:
One poll of a task, which runs it from where it suspended to its next `await` that isn't done ([07](docs/spec/07-concurrency/tasks.md#task-functions-coroutines-that-wait-without-a-thread)). `TaskSet`'s `step` gives one to each task woken since the last.

**Synchronized**:
A type whose non-`mutating` methods change it only through its own synchronization, such as a `Mutex` or a queue, so threads can share it ([07](docs/spec/07-concurrency/synchronization.md#the-synchronized-contract)).
_Avoid_: concurrent type

**Task**:
The value a `task func` call returns: a coroutine whose size is known at compile time, which its runner steps until it finishes ([07](docs/spec/07-concurrency/tasks.md#task-functions-coroutines-that-wait-without-a-thread)).
_Avoid_: async function, future (a `Future` is one awaitable), state machine value

**Teardown**:
The end of a thread's Rayo code, which destroys its copies of the thread-locals and its objects, on that thread ([07](docs/spec/07-concurrency/global-state.md#thread-teardown)).

**Thread identity**:
What tells a thread running Rayo code from every other thread of the run, and from its own earlier attachments, however it started ([07](docs/spec/07-concurrency/global-state.md#thread-identity)).
_Avoid_: thread id

### C interop

**C entry**:
A function C can call: a `@c func`, an `@export` function, or a closure literal converted to a `@c` pointer ([08](docs/spec/08-c-interop/calling-rayo-from-c.md#c-entries-and-threads)).

**Config block**:
The `unsafe { … }` block that may end an `import c`, holding rules about the header's C ([08](docs/spec/08-c-interop/imports-and-inline-c.md#importing-headers)).

**Memory location**:
A maximal run of adjacent nonzero-width C bitfields, which counts as one place for exclusivity ([08](docs/spec/08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)).

**Open enum**:
An imported C enum, which may hold any value of its underlying type unless its header declares it closed ([08](docs/spec/08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)).

### Compile time

**Freezable**:
Said of a value that can be frozen: copied into read-only data, where it stays unchanged for the whole run, as a `const` that reaches run time must be ([09](docs/spec/09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).

**Immortal data**:
Memory that is never freed, and that nothing writes once a value names it, such as a literal's bytes, which a `StaticSpan` or a `StaticString` views ([09](docs/spec/09-compile-time/attributes-and-runtime-data.md#staticspan-views-of-immortal-data)).

**Reaches run time**:
Said of a `const` named anywhere but in a `const` initializer, a `static if` or `static for` condition or list, an attribute argument or a `const` argument; the compiler copies it into read-only data ([09](docs/spec/09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).

**Static closure**:
A closure whose body is instantiated once per field, as the argument of `T.construct` or `T.makeCase` ([09](docs/spec/09-compile-time/reflection.md#constructing-values-reflectively)).

### Errors and safety

**Allocation**:
One block of storage that accesses stay inside, and that is live or freed as a whole ([10](docs/spec/10-errors-and-safety/unsafe-code.md#allocations)). It is storage an allocator gave out, a local, a temporary or a global, or memory that C, the platform or a device provides.

**Build mode**:
`debug` or `release`: the first turns every diagnostic check on by default, and the second every one off ([10](docs/spec/10-errors-and-safety/checks-and-build-modes.md#build-modes)).
_Avoid_: build profile, configuration

**Diagnostic check**:
A run-time check that catches a logic bug whose failure is still memory-safe, such as integer overflow; `@checks`, a module's settings and the build mode turn each one on or off ([10](docs/spec/10-errors-and-safety/checks-and-build-modes.md#check-levels)).
_Avoid_: debug check

**Error union**:
A tagged union with one member per error type, written `(IoError | ParseError)`, as in `Level!(IoError | ParseError)` ([10](docs/spec/10-errors-and-safety/typed-errors.md#error-unions)).

**Failure type**:
The `Failure` of a `Result`, and of a function whose result type is one: the errors it can fail with, `Never` for none ([10](docs/spec/10-errors-and-safety/typed-errors.md#results)).

**Memory-safety check**:
A run-time check, such as a bounds check, that keeps safe code sound; it is on in every build ([10](docs/spec/10-errors-and-safety/checks-and-build-modes.md#check-levels)).
_Avoid_: safety check

**Panic**:
How a bug, such as unwrapping `nil` with `!`, stops the code that hit it: reported through the platform, it unwinds the thread until a recovery point stops it or the thread ends ([10](docs/spec/10-errors-and-safety/panics.md#panics)).
_Avoid_: crash, exception

**Panic strategy**:
The build's choice of how a panic ends: by unwinding, the default, or by aborting, which reports the panic and ends the program at once, so nothing catches it ([10](docs/spec/10-errors-and-safety/panics.md#panic-strategy)).

**Recoverable error**:
A typed value, such as a missing file, that a function returns as the failure of its `Result` and its caller must handle ([10](docs/spec/10-errors-and-safety.md)).
_Avoid_: exception

**Recovery point**:
A call of `catchPanic`, where an unwind out of its body stops and its `recover` closure runs with the panic ([10](docs/spec/10-errors-and-safety/panics.md#catching-a-panic-catchpanic)).
_Avoid_: catch block, landing pad

**Result**:
The prelude's enum `Result<Success, Failure>`, written `Success!Failure`, which a function that can fail returns: its result as `.success` or its error as `.failure` ([10](docs/spec/10-errors-and-safety/typed-errors.md#results)).

**Unsafe code**:
Code that uses an operation needing `unsafe`, such as dereferencing a raw pointer or calling C, whose soundness the code promises instead of the compiler ([10](docs/spec/10-errors-and-safety/unsafe-code.md#unsafe-code)).

**Unsafe protocol**:
A protocol, such as `Sendable` or `Frozen`, whose declared conformance is a contract the compiler can't check ([10](docs/spec/10-errors-and-safety/unsafe-code.md#unverified-promises)).

**Unverified promise**:
A declaration the compiler takes on trust, such as an `unsafe` conformance, an `@export` function or an `import c` config block ([10](docs/spec/10-errors-and-safety/unsafe-code.md#unverified-promises)).

**Unwinding**:
What a panic does to its thread's frames, innermost first: it ends each as a `throw` would, destroying its live values and running its live `defer` blocks ([10](docs/spec/10-errors-and-safety/panics.md#unwinding)).

### Compilation

**Pointer width**:
The size of a target's pointers and of C's size types, 32 or 64 bits, which `Int` and `UInt` don't follow ([11](docs/spec/11-compilation-model.md#what-a-target-must-provide)).
_Avoid_: word size, bitness

**Prelude**:
The std declarations every module sees without an import ([11](docs/spec/11-compilation-model.md#the-prelude)).
