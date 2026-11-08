# Panics

[10 · Errors and safety](../10-errors-and-safety.md)

A panic stops an operation that cannot continue under the language's rules. It does not return a value for the caller to handle, as a typed error does. It can follow an explicit precondition or a failed check built into an operation:

```swift
let e = borrow enemies[h]!                       // panics if h is stale
precondition(count < capacity, "queue full")     // panics if the caller broke the contract
let share = total / players                      // panics if players is 0, in every build
```

**A panic is reported through the platform ([08](../08-c-interop/c-contract-and-embedding.md#what-the-runtime-needs-from-the-platform)), and never returns.** Nothing unwinds, so no frame's borrows end early, no `deinit` runs on a half-changed value, and work the panicking thread lent out still finds its memory.

## What panics

**The language and the runtime panic in the cases below, in every build unless noted, except where an `unchecked` block removes the check ([`unchecked` blocks](checks-and-build-modes.md#unchecked-blocks)).**

**Failures the code asks for:**

- `fatalError("…")`, `precondition(cond, "…")`, `x!` on `nil`, `try!` on an error;
- a failing `assert(cond)`, where assertions are checked ([below](#assert-and-precondition));
- `unreachable()` reached.

**Arithmetic:**

- integer overflow, including unary `-` and `Int.min / -1`, an unlabeled integer conversion whose value doesn't fit, and an imported bitfield write that doesn't fit its width ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)), only where overflow checks are on ([04](../04-types/numbers-and-math.md#integer-overflow-division-and-shifts));
- division or remainder by zero, and converting NaN or an out-of-range floating-point value to an integer with the unlabeled form.

**Uses out of bounds, or outside a value's life:**

- out-of-bounds indexing, and a string range off a Unicode scalar boundary ([04](../04-types/collections.md#strings));
- an access through, or a pin taken through, a stale object owner ([03](../03-handles-and-objects.md#destroying-an-object));
- opening an owning value whose allocator was reset or unregistered since ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it));
- reading a global before its initializer has run ([07](../07-concurrency/global-state.md#initialization-at-startup));
- using a thread-local before its thread's copy is initialized or after it is destroyed ([07](../07-concurrency/global-state.md#thread-locals));
- polling a task that has already finished ([07](../07-concurrency/tasks.md#semantics)).

**Conflicting uses:**

- conflicting accesses to a thread-bound object ([03](../03-handles-and-objects.md#dynamic-exclusivity)) or a thread-local ([07](../07-concurrency/global-state.md#thread-locals));
- destroying a thread-bound object while an access to it is live ([03](../03-handles-and-objects.md#destroying-an-object));
- taking a `Mutex`'s or an `RwLock`'s exclusive access on a thread that holds any access to it, or any access on a thread that holds its exclusive one, since that conflicts with a view the thread holds ([07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock));
- `lock()` on a `Slice` of a bare `Shared<Blob>`, since nothing writes a `Frozen` value ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers));
- overlapping calls on one side of a single-producer or single-consumer queue, so that its algorithm never sees two producers or two consumers at once ([07](../07-concurrency/synchronization.md#queues-and-channels)).

**Running out:**

- running out of stack, each case caught before anything is written past the stack's end:
    - a call, or the destruction of deeply nested values, that needs more of the stack it runs on than is left, a fiber's stack that C declared included;
    - a call into C made with less stack left than its target declares, or than `target.cStackReserve` when it declares nothing ([08](../08-c-interop/imports-and-inline-c.md#the-stack-a-c-call-needs));
- a count kept for safety that would overflow:
    - the reader counts of an object, a thread-local and an `RwLock` ([03](../03-handles-and-objects.md#dynamic-exclusivity), [07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock));
    - pin counts ([03](../03-handles-and-objects.md#pinning-for-c));
    - a thread's counts of its uses of an allocator ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it));
    - the counts behind `Shared`, `LocalShared`, `Published` snapshots, and `Sender`, `Receiver` and `Future` values ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners), [07](../07-concurrency/synchronization.md#queues-and-channels));
- creating an object or a `Shared` value when no generation is left, so that no weak pointer or weak link names a later one ([03](../03-handles-and-objects.md#destroying-an-object), [06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners));
- an allocation that fails in a plain form, such as `UniquePointer(v)` or a closure context past the inline budget ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)).

**Misused allocators:**

- any operation through an unregistered `Allocator` id, apart from the frees and growths that 06 allows from the `deinit`s its unregistration runs ([06](../06-memory-and-allocators/arena-safety.md#unregistering-an-allocator));
- a reset or a `release` through an allocator that isn't an arena, since both are arena operations ([06](../06-memory-and-allocators/arena-safety.md#what-a-reset-does));
- a reset past the implementation's limit on resets, so that no allocator word is issued twice ([06](../06-memory-and-allocators/arena-safety.md#what-a-reset-does));
- a reset or an unregistration while anything still uses the memory it would free, or while another that reaches that memory is running ([06](../06-memory-and-allocators/arena-safety.md#what-a-reset-does));
- unregistering `.system`, so that its storage never goes stale ([06](../06-memory-and-allocators/allocator-basics.md#allocator-values));
- registering an allocator whose backing is unregistered, or whose backing chain breaks a rule for backing chains ([06](../06-memory-and-allocators/allocator-implementations.md#allocators-over-other-allocators));
- registering an allocator past the implementation's limit, so that no allocator word is issued twice ([06](../06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator)).

**Startup, shutdown and threads from C:**

- entering Rayo from C before startup has finished or after shutdown, except a nested entry ([07](../07-concurrency/global-state.md#initialization-at-startup));
- calling `rayo_init` a second time, and detaching a thread or calling `rayo_shutdown` on a thread with a Rayo frame on any of its stacks, since those frames may still use what detaching or shutting down destroys ([08](../08-c-interop/c-contract-and-embedding.md#embedding-rayo-in-a-c-program));
- a wait during startup that would park with no timeout, since no other thread runs Rayo code during startup ([07](../07-concurrency/global-state.md#initialization-at-startup)), and a thread queued during startup that the platform can't start when startup ends ([07](../07-concurrency/thread-work.md#starting-a-thread-runtimestartthread)).

**Names.** `Name(s)` panics when another text already has `s`'s hash, since no two texts share a `Name` ([04](../04-types/collections.md#collections-and-strings)).

## What a panic does

When a thread panics, on its own or with others:

- **The first panic is the one reported.** A thread that panics after it stops without reporting.
- **The program then ends, once the report is made.**
- **Every other thread stops.** Where the platform can suspend threads, each stops where it stands, lent work included, so the report can show its stack as it was. Elsewhere, each stops the next time it enters Rayo from C or parks, or when the program ends, so a thread deep in a long computation may run briefly after the panic.

## `assert` and `precondition`

```swift
mutating func push(_ item: owned Item) {
    precondition(count < capacity, "ring buffer full")    // an API contract: checked in every build
    assert(invariantsHold())                              // an internal invariant, costly to test: debug builds by default
    unsafe { (storage + tail).initialize(to: item) }      // relies on the precondition
    ...
}
```

**`precondition` checks a contract with the caller, and `assert` an internal invariant that may be costly to test.** Both panic when their condition is false, and they differ in which builds check them:

- **`assert(cond)`** is a diagnostic check, checked by default only in `debug` builds. A module or a scope can turn it on in `release` builds too, through the build's settings or `@checks(.all)` ([Choosing checks for a module or a scope](checks-and-build-modes.md#choosing-checks-for-a-module-or-a-scope)).
- **`precondition`** is checked in every build, and only `unchecked` code can strip it ([`unchecked` blocks](checks-and-build-modes.md#unchecked-blocks)), so `unsafe` code after one may rely on its condition.
