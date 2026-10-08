# Runtime values and concurrency

[13 · Soundness](../13-soundness.md)

## Closures and function values

**This section keeps Covered, Exclusive and Race-free.** A closure's storage holds its captures, and a function value is a view of that storage, so the rules for views and for method bodies apply to closures too.

- **A function value is a view of its closure's storage** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)), so it is scoped and depends on that storage, which lives in a hidden local of the scope or as a temporary of the statement.
- **A closure body is checked as a method whose `self` is the closure** ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-5-the-callee-side)). Owned captures are an owned parameter's storage, since a call through a `consuming` type destroys them, so nothing it returns views them. A store into a capture can't depend on a place captured exclusively, since the next call may change or free it, unless the closure is `consuming` and runs once.
- **Parameters are call-scoped unless `keep`** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)), so a closure lent data for one call, such as a lock's, can't keep a view of it. A `keep` argument's set joins everything the closure depends on exclusively, and the calling function's rule 5 must allow that store. A borrowed `keep` parameter's own storage belongs to the call, so only what it carries flows.
- **The kind says how a closure may be called** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)):
    - a non-`mutating` closure only reads its captures, so any number of threads may call it at once, and a comparator can't write what it reads;
    - a `mutating` one is move-only and lent exclusively, since calling it changes the closure itself;
    - a `consuming` one is called at most once, which is what lets it move out of its captures.

  A conversion only strengthens the kind and never adds ownership.
- **No conversion applies through `mutable`** ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). Otherwise the callee could store a value of the wider type into a variable the caller still sees as the narrower one, such as a `mutating` closure into one that a job system calls on many threads. The exceptions make new views, each lending its place until the view's last use.
- **A closure captures places as precisely as overlap keeps them apart** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#capturing-places)), stopping before accessors, optional chains, payloads and object accesses, which the body evaluates on each call. A captured borrowing binding brings its set and its dynamic accesses, held while the closure lives.
- **`Closure<F>` owns and lists its captures**, so it borrows nothing ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)). Its out-of-line context is checked at each call as any open is. It counts as holding a `Synchronized` value, since its captures may. So it is always the caller's place, and never packed, since a `Synchronized` value needs its alignment ([Types and layout](types-and-boundaries.md#types-and-layout)).
- **Calls of `unsafe` and C functions stay visible.** No function value hides an `unsafe` call, and C converts only to `@c` types, which carry the stack need its calls check ([05](../05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers)).

## Generic code and existentials

**One check of a generic body must hold for every type it may be instantiated with, and an existential hides its type until run time.** So neither may assume more about a type than its constraints say:

- **Generic code is checked once, at the safe bound** ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)). An unconstrained type parameter may be any of these:
    - move-only;
    - scoped;
    - a mutable view;
    - not `Sendable`;
    - a type with a `deinit` whose destruction is a use.

  So a body that checks under those assumptions is sound for every instantiation. Each constraint, such as `Copyable`, `~Scoped`, `TrivialFree` or `Sendable`, relaxes one assumption, and every instantiation meets it. Members a `static if` or `static for` generates are taken at the same bound ([09](../09-compile-time/declaration-generation.md#generated-members-are-checked-per-instantiation)).
- **A witness keeps its requirement's promises**: conventions, `where` clauses, storage or access-bound projections, and `@noalloc`. So generic code relies only on the requirement.
- **`~Copyable`, `~Sendable`, `Scoped` and `Synchronized` are declared unconditionally** ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#conformances)). Generic code derives copyability, sendability and scope from fields, type arguments and these declarations for every type argument at once, so no instantiation can differ from what it checked.
- **`any P` is a view** ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)): made from a shared borrow, or from `&x` as a `mutable any P`, so the rules above apply to it. An unscoped existential, such as `Box<any P>`, forgets its value's type and what that type carries, so the type must be unscoped, `~Scoped`. An existential is `Sendable`, `Frozen` or `TrivialFree` only when its protocols say so, since it hides a type that may not be.

## The dynamic tier

**Each mechanism checks at each use what the static tier can't see, and a failure panics or reads `nil` before it touches memory.** So each keeps an invariant at run time where the static checker can't prove it ([01](../01-values-and-ownership.md#tiers-of-checking)):

- **Handles** ([03](../03-handles-and-objects.md#pools-and-handles)). A pool's subscript checks the slot's generation, and a slot whose generation would wrap is abandoned, so a stale handle reads `nil` for good. A forged one reaches `nil` or some live element of that pool, so it keeps **Live** and **Valid**, if not the element meant. The subscript is a storage projection of the pool, so removing an element conflicts statically with every live view of one.
- **Object liveness** ([03](../03-handles-and-objects.md#destroying-an-object)). A weak pointer names its object by a generation that no other object of the run gets, so it never reaches a later object. An owner whose object a reset or an unregistration destroyed is stale, and an access through it panics. So no access reaches a destroyed object, or the memory freed with it: **Owned** and **Live**.
- **Object marks** ([03](../03-handles-and-objects.md#dynamic-exclusivity)). Weak pointers are aliases the checker can't see, so each access takes a mark, held as rule 6 says. A conflicting one panics before it touches the value: **Exclusive**. The counts can't wrap.
- **Destruction never frees under an access** ([03](../03-handles-and-objects.md#destroying-an-object)). Destroying an object while an access to it is live panics. A pin leaves the `deinit` and the release to the last pin's drop. So the `deinit` runs once, when no access is live and no pin holds the value, and the memory is freed after it: **Owned** and **Live**.
- **Thread-bound objects stay home**, which keeps **Race-free** ([03](../03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)). Their marks aren't atomic, so two threads taking marks on one object would race. These rules keep every object's uses on its home thread:
    - owners, weak pointers and `LocalPin`s aren't `Sendable`;
    - `WeakPointer(bits:)` and `adopt` check the home thread;
    - a home thread's identity is never reused;
    - the `deinit` runs on that thread, since a reset or an unregistration on another panics instead;
    - a thread's objects end in its teardown, on it.
- **Reference counting** ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)). A `Shared`'s count is atomic, and a `LocalShared`'s never leaves its thread. So the value is destroyed once, by the drop that takes the count to zero, after every other owner's drop in happens-before order: **Owned** and **Live**. A weak link names its value by a generation that no other `Shared` value of the run gets. `upgrade()` adds an owner only while the count is above zero, in one atomic step. So a weak link never reaches a destroyed or a later value. A `Waker` reaches its target through such an upgrade.
- **Pins** ([03](../03-handles-and-objects.md#pinning-for-c)). A pin keeps its memory from being freed or reused, so the address C holds stays in a live allocation, as C needs to keep **Live** ([The unsafe boundary](types-and-boundaries.md#the-unsafe-boundary)). Destroying a pinned value leaves the `deinit` and the release to the last pin's drop, which happens on a thread the value may be destroyed on. A reset or an unregistration panics while a pin into its memory lives. Each drop happens before the release that waited for it. A pin doesn't make the value immutable: Rayo code still writes it through its owner, under the rules above.
- **`Slice`** ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)). It reaches its buffer only through a scoped span per use, so it may be stored anywhere. Each `read()` or `lock()` upgrades its weak link and checks the storage's word. For a locked buffer, it also takes the lock and checks the current length, alignment or count under it. The span then holds the owner and the lock. `T` is `Pod` over initialized bytes, so every element read is **Valid**. A `MutableSpan` also needs `T` padding-free, so a store leaves no uninitialized byte another slice reads.
- **Thread-locals** ([07](../07-concurrency/global-state.md#thread-locals)). Each access to a thread's copy takes a mark, as an object's does: **Exclusive**. The copy is initialized before any other code of its thread runs, and marked dead before it is destroyed, so a later `deinit` that reaches it panics.
- **Locks** ([07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock)). Taking a lock that the thread holds in a conflicting way panics, lent work the lending thread runs included, so no thread gets a second exclusive view: **Exclusive**.

## Memory and allocators

**This section keeps Live for memory released out of band, by a reset or an unregistration.** A reset frees everything an arena handed out at once, but it can't find the values in that memory, which may be anywhere ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)). So two run-time checks take the place of the static ones: each use of the memory checks that its storage isn't stale, and the reset checks that nothing uses it.

- **Every release happens at a point the code shows** ([06](../06-memory-and-allocators.md)). An owner's release, the last of a reference-counted value's owners included, is a mutable access, checked statically. A reset or an unregistration first checks that nothing uses the memory (below).
- **An open checks the storage's word, and counts as a use while what it lends lives** ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)). A reset can't find the values it invalidates, so every access that reaches their storage checks first. Nor can it find their views, so each open counts itself until the last use of what depends on it, as rule 6 holds a dynamic access. A reset or an unregistration makes the storage stale before it reads the counts, so an open racing it either fails or is counted. A container's words cover all of its storage.
- **Uses are counted on every thread.** Lent work's views depend on the lender's opens, which count until the lending call returns, and its own opens count on the thread that makes them ([07](../07-concurrency/thread-work.md#the-librarys-promise)). A parked thread keeps its counts.
- **A word is never issued twice** ([06](../06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator)): the limits on registrations and resets panic, so a stale word never passes again, outside the `deinit`s that may open what they own.
- **A reset frees its blocks only once nothing uses them** ([06](../06-memory-and-allocators/arena-safety.md#what-a-reset-does)). The runtime, not the arena, decides what is stale, by stamps it issues in order and never twice. A reset panics while any of these still uses the memory:
    - a counted open;
    - a pin;
    - an accessed object;
    - another thread's object.

  It also panics while another reset or unregistration that reaches the memory runs. It frees the blocks only after the `deinit`s it runs have returned. Unregistering checks, and waits for its `deinit`s, the same way ([06](../06-memory-and-allocators/arena-safety.md#unregistering-an-allocator)).
- **Destroying a stale value never touches its memory** ([06](../06-memory-and-allocators/arena-safety.md#stale-values-and-the-deinits-a-reset-runs)), since that memory may already be reused. So its elements' `deinit`s are skipped and what they owned leaks.
- **An object's `deinit` that a reset or an unregistration runs may open what that reset or unregistration made stale.** The memory is freed only after the `deinit` returns, and a value an earlier reset made stale still fails, since its memory may already be reused.
- **Backing chains are fixed and acyclic** ([06](../06-memory-and-allocators/allocator-implementations.md#allocators-over-other-allocators)), so a reset or an unregistration reaches everything built on it, and no arena or heap draws from an arena, whose reset would reuse memory under it.
- **`AllocatorImpl` is a promise** ([06](../06-memory-and-allocators/allocator-implementations.md#what-conforming-promises)): disjoint allocations, no reuse after handing a block over, and truthful reports. It is `Synchronized`, since any thread allocates ([06](../06-memory-and-allocators/allocator-basics.md#allocators-and-threads)).
- **A `Shared<T>` holds a `Frozen` or `Synchronized` value, and a `LocalShared<T>` a `Frozen` one** ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)). So what many owners reach is never written, or written only through its own synchronization, apart from the count, which no reader observes. `Frozen` is derived only for types with no interior mutability, and nothing holding a `Synchronized` value is `Frozen` ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)).
- **`release` forgets only a `TrivialFree` value** ([06](../06-memory-and-allocators/allocation-lifecycle.md#releasing-a-value-without-destroying-it-trivialfree)), whose destruction would only free memory, which the reset then frees.
- **A failed allocation panics or throws** ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)), so no operation goes on with memory it didn't get.

## Threads

**This section keeps Race-free.** Only `Sendable` values reach another thread. Everything else stays on its own thread, where exclusivity and the dynamic tier check all its aliases ([07](../07-concurrency/race-freedom-and-sendable.md#why-safe-code-cant-race)).

**`Sendable` is derived from what a type holds** ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)), so a value's type says whether it reaches anything bound to a thread. Object pointers, `LocalPin`s and guards never are, since their marks and locks belong to one thread, and raw pointers are only by promise.

**Safe code on two threads reaches the same memory only through four routes, each of which orders its writes:**

- **Borrows lent for a call.** The library promises these ([07](../07-concurrency/thread-work.md#the-librarys-promise)):
    - to move only `Sendable` values;
    - to call each closure as its kind allows;
    - to hand values over in happens-before order;
    - to have every thread done with a value before the borrows it carries end.

  The closures the library is lent are borrows of the call's arguments, so exclusivity holds across them statically. A value it keeps past the call is kept in a scoped, unsealed type, which absorbs what the value borrows.
- **`Synchronized` values and channel ends.** The contract ([07](../07-concurrency/synchronization.md#the-synchronized-contract)) is a list of what Race-free and Exclusive need of shared mutable state:
    - move-only, so every thread synchronizes on the same memory;
    - no niche, since reading a tag is a plain load of bytes other threads write;
    - unscoped, `Sendable` contents, since they reach other threads and absorption can't follow them through a shared `self`;
    - every field its synchronization writes is `unsafe` or `Synchronized`, so safe code never reads one with a plain load, and the type is never `Frozen` or `Pod`;
    - values taken in and handed out owned, in happens-before order;
    - no view granted while a conflicting one is live, on any thread, which a re-entrant lock can't meet;
    - guards declared `@guard`, so each is released on the thread that took it, pointing only into the lock, which keeps what they view allocated;
    - views of its interior only under a lock, or of data never written again except through its own synchronization and never freed before the value is destroyed;
    - bitwise-movable whenever unborrowed, since the language moves only unborrowed values.

  A channel's ends are `mutating` on each side, so exclusivity makes one consumer and one producer at a time, statically ([07](../07-concurrency/synchronization.md#queues-and-channels)).
- **`Shared` values**, whose value is `Frozen`, so never written, or `Synchronized`, so written only through its own synchronization ([above](#memory-and-allocators)).
- **`const`s, global `let`s and immortal data**, read through shared borrows and changed only through their own synchronization ([07](../07-concurrency/global-state.md#global-state)).

**No other global is reachable from safe code.** A bare global `var` needs `unsafe`, and a `@threadlocal var` gives each thread its own copy. A static stored member is never declared where one declaration stands for many instances, since each instance would need its own, initialized in no one module's turn ([07](../07-concurrency/global-state.md#global-state)).

**Startup is single-threaded** ([07](../07-concurrency/global-state.md#initialization-at-startup)), and its end happens before every later entry into Rayo code on another thread. A global read before its initializer has run is caught, statically where the calls are visible, and at run time otherwise.

**Atomics follow the C++20 memory model** ([07](../07-concurrency/synchronization.md#atomics-and-locks)). The creation of a `Shared` value, an allocator or a `Name` happens before every use of it, however the value naming it arrived, since the check each use makes synchronizes with the creation.

**A task holds no borrow across an `await`** ([07](../07-concurrency/tasks.md#semantics)). Its owner may move or destroy its state between steps. Its own locals are worked out again on resuming, since only its body reaches them, and its resume parameter is lent anew at each step. Its parameters are owned and unscoped, a `defer` live across an `await` uses only its state, and a finished task panics when polled.
