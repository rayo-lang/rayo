# Panics

[10 · Errors and safety](../10-errors-and-safety.md)

A panic stops an operation that cannot continue under the language's rules. It does not return a value for the caller to handle, as a typed error does. It can follow an explicit precondition or a failed check built into an operation:

```swift
let e = borrow enemies[h]!                       // panics if h is stale
precondition(count < capacity, "queue full")     // panics if the caller broke the contract
let share = total / players                      // panics if players is 0, in every build
```

**A panic is reported through the platform ([08](../08-c-interop/c-contract-and-embedding.md#what-the-runtime-needs-from-the-platform)), then unwinds the thread that panicked.** The thread leaves its frames as a `throw` leaves scopes, destroying what each one owns, until a recovery point stops it or the thread ends ([below](#what-a-panic-does)). So the code that panicked never goes on, and a program can still recover from a bug in one part of its work:

```swift
do {
    try catchPanic { handle(request) }
} catch let p as Panic {
    log("request failed: \(p.reason)")       // the server goes on to the next request
}
```

A few failures can't unwind, and end the program at once instead ([below](#what-ends-the-program)).

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

- a count kept for safety that would overflow:
    - the reader counts of an object, a thread-local and an `RwLock` ([03](../03-handles-and-objects.md#dynamic-exclusivity), [07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock));
    - pin counts ([03](../03-handles-and-objects.md#pinning-for-c));
    - a thread's counts of its uses of an allocator ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it));
    - the counts behind `Shared`, `LocalShared`, `Published` snapshots, and `Sender`, `Receiver` and `Future` values ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners), [07](../07-concurrency/synchronization.md#queues-and-channels));
- creating an object or a `Shared` value when no generation is left, so that no weak pointer or weak link names a later one ([03](../03-handles-and-objects.md#destroying-an-object), [06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)).

Running out of stack, and an allocation that fails in a plain form, end the program instead ([below](#what-ends-the-program)).

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

**Poisoned locks.** `lock` on a `Mutex` or an `RwLock` that an unwind released panics until `clearPoison()` resets it ([below](#unwinding)).

**Names.** `Name(s)` panics when another text already has `s`'s hash, since no two texts share a `Name` ([04](../04-types/collections.md#collections-and-strings)).

## What a panic does

**A panic runs these steps on the thread that panicked:**

1. **It is reported** through the platform as it happens, whether or not a recovery point catches it later.
2. **It unwinds the thread**, one frame at a time, innermost first ([below](#unwinding)).
3. **It stops at the innermost recovery point** on the thread, which throws it as a `Panic` error ([below](#catching-a-panic-catchpanic)). With none, the unwind reaches the thread's first frame, and the thread ends ([below](#uncaught-panics)).

### Unwinding

**Unwinding a frame ends it as a `throw` that nothing catches would.** It destroys each live value the frame owns and runs each live `defer` block, in the order a scope's end destroys them ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction-by-unwinding)). That covers the temporaries of the statement the panic interrupted, and a value that holds only some of its fields, which loses exactly those.

**Unwinding ends what each frame began, as a return would:**

- **Borrows and views** end with the frame, as the values that hold them are destroyed.
- **Dynamic accesses** release their marks ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)), and opens of owning values stop counting as uses of their allocators ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).
- **Lock guards** release their locks. A lock released this way is poisoned, so the next `lock` on it panics until `clearPoison()` resets it, and no code takes what the panic left half-changed for a whole value ([07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock)).

**Every point that can panic is an exit for the rules that check exits.** Those points are the operations that [What panics](#what-panics) lists, and every call, since the callee may panic. So an unwind never breaks a rule that a return keeps:

- a `defer` body is checked as if written at each of them too ([Cleanup](typed-errors.md#cleanup));
- a scoped `mutable` parameter counts as used at each of them, so a callee never leaves its caller a view of what it freed ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)).

**A panic in a `deinit` or a `defer` block unwinds as any panic does, unless an unwind is running that block.** The unwind still destroys the rest of the value whose `deinit` panicked, its fields after its `deinit`, and every other live value. A panic that would unwind out of a `deinit` or a `defer` block that an unwind runs ends the program instead ([below](#what-ends-the-program)), since a recovery point catches one panic, and the thread would carry two.

### Uncaught panics

**A panic that no recovery point catches ends its thread.** The unwind destroys the thread's first frame too, and the thread's teardown then runs as when its body returns ([07](../07-concurrency/global-state.md#thread-teardown)). How the end of a thread reaches the code that started it or lent it work is in 07 ([07](../07-concurrency/thread-work.md#lending-work-and-starting-threads)).

**On the main thread, the program then shuts down as when `main` returns, and exits with status 101.** Shutdown runs the main thread's teardown and closes entry from C ([07](../07-concurrency/global-state.md#shutdown)).

## What ends the program

**These failures end the program at once, without unwinding:**

- **Running out of stack.** Unwinding runs `deinit`s and `defer` blocks, which need the stack that ran out. Each case is caught before anything is written past the stack's end:
    - a call, or the destruction of deeply nested values, that needs more of the stack it runs on than is left, a fiber's stack that C declared included;
    - a call into C made with less stack left than its target declares, or than `target.cStackReserve` when it declares nothing ([08](../08-c-interop/imports-and-inline-c.md#the-stack-a-c-call-needs)).
- **An allocation that fails in a plain form**, such as `UniquePointer(v)` or a closure context past the inline budget. Code that can recover uses a fallible form, which returns `nil` or throws ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)).
- **A panic that would unwind out of a `deinit` or a `defer` block that an unwind runs** ([above](#unwinding)).
- **A panic that would unwind into C**: out of an `@export` or `@c` function, or a closure literal converted to a `@c` type. C has no way to unwind its frames or run their cleanup ([08](../08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c)).
- **Every panic, under the abort strategy** ([below](#panic-strategy)).

**Ending the program runs these steps:**

- **The failure is reported.** A panic was reported when it happened, and any other failure is reported now. Once one failure is ending the program, a thread that fails or panics after it stops without reporting.
- **The program ends once the report is made.** No frame unwinds and no shutdown runs, so no `deinit` or `defer` block runs either.
- **Every other thread stops.** Where the platform can suspend threads, each stops where it stands, lent work included, so the report can show its stack as it was. Elsewhere, each stops the next time it enters Rayo from C or parks, or when the program ends, so a thread deep in a long computation may run briefly after the failure.

## Catching a panic: `catchPanic`

```swift
func catchPanic<R, E: Error>(_ body: consuming () throws(E) -> R) throws(Panic | E) -> R

let saved = try? catchPanic { autosave(game) }     // nil if autosave panicked
```

**`catchPanic(body)` calls `body` as a recovery point.** A **recovery point** is where an unwind stops. When `body` returns or throws, `catchPanic` returns or throws the same. When a panic unwinds out of `body`, `catchPanic` throws it as a `Panic`, once the unwind has destroyed `body`'s frames and the closure itself. So `try`, `try?`, `try!` and `do`/`catch` apply to it unchanged ([Typed `throws`](typed-errors.md#typed-throws)).

- **The innermost one catches.** A panic unwinds to the innermost `catchPanic` on its own thread, and a panic on another thread never reaches it.
- **Catching undoes nothing.** The report was made when the panic happened, and the values the unwind destroyed stay destroyed.
- **Not at compile time.** A panic during compile-time evaluation is a compile error, and `catchPanic` can't run there ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)).
- **Not under the abort strategy**, where a panic ends the program before it can reach a recovery point ([below](#panic-strategy)).

**A `Panic` holds the panic's reason and where it happened:**

```swift
struct Panic(let reason: StaticString, let location: SourceLocation): Error
struct SourceLocation(let file: StaticString, let line: Int, let column: Int)
```

- **The reason** is the text passed to `fatalError` or `precondition`, each of which takes a `StaticString`. A check the language makes gives a fixed reason that names the check, such as `"index out of range"`. So making a `Panic` never allocates.
- **The location** is that of the call to `fatalError`, `precondition` or `assert`, or of the operation whose check failed.
- **It is copyable and `Sendable`**, since all its fields are, so one thread can hand another the panic it caught ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).

### What the closure may change

**`catchPanic`'s closure may depend on no place exclusively, so code after the recovery point never sees a value that the panic left half-changed.** A closure depends on a place exclusively when it captures it exclusively ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)), or holds an exclusive view of it, such as a `MutableSpan` ([02](../02-views-and-dependencies/dependency-projection-and-results.md#mutable-views)):

```swift
do {
    try catchPanic { world.step(dt) }                          // error: the closure captures 'world' exclusively
} catch let p as Panic { log("step failed: \(p.reason)") }

do {
    try catchPanic { [unwindSafe &world] in world.step(dt) }   // fine: the caller vouches for 'world'
} catch let p as Panic {
    world.resetPhysics()                                       // and repairs what the panic may have left
}
```

**`unwindSafe` in the closure's capture list lifts the rule for one capture.** `[unwindSafe &world]` captures `world` exclusively, as the body would, and `[unwindSafe move rows]` moves `rows` in, as `[move rows]` does. Either way, the caller takes on what the rule checks: that the code after the recovery point copes with whatever the panic left there. `unwindSafe` appears only in a closure literal written as `catchPanic`'s argument.

**A function value may carry exclusive dependencies its caller lent**, so a function that passes one on to `catchPanic` marks it the same way:

```swift
func guarded(_ body: consuming () -> Void) {
    do {
        try catchPanic { [unwindSafe move body] in body() }    // 'body' may change the caller's places
    } catch let p as Panic { log("guarded work failed: \(p.reason)") }
}
```

**The rule guards what code sees, not memory safety.** A value that a panic interrupts in safe code is still a valid value of its type, and `unsafe` code keeps it one ([Unsafe code](unsafe-code.md#values-views-and-threads)). So `unwindSafe` needs no `unsafe`.

**State that changes through a shared path is outside the rule.** An object's value, a thread-local and a `Synchronized` value change with no exclusive capture ([01](../01-values-and-ownership/bindings.md#changeable-places)), so the closure may still leave one half-changed. A lock among them is poisoned ([above](#unwinding)), and code after the recovery point checks the rest itself.

## Panic strategy

**The panic strategy says how a panic ends: by unwinding, the default, or by aborting.** A build chooses it with its other settings ([09](../09-compile-time/attributes-and-runtime-data.md#what-a-build-declares)). Under the **abort** strategy, every panic is reported and ends the program at once, as the failures above do ([above](#what-ends-the-program)). So `catchPanic` never catches: it calls its closure, and returns or throws what the closure does.

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
