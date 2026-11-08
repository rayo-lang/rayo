# Panics

[10 · Errors and safety](../10-errors-and-safety.md)

A panic stops an operation that cannot continue under the language's rules. It does not return a value for the caller to handle, as a typed error does. It can follow an explicit precondition or a failed check built into an operation:

```swift
let e = borrow enemies[h]!                       // panics if h is stale
precondition(count < capacity, "queue full")     // panics if the caller broke the contract
let share = total / players                      // panics if players is 0, in every build
```

**A panic is reported through the platform ([08](../08-c-interop/c-contract-and-embedding.md#what-the-runtime-needs-from-the-platform)), then unwinds the thread that panicked.** The thread leaves its frames as a `throw` leaves scopes, destroying what each one owns, until a recovery point ([below](#catching-a-panic-catchpanic)) stops it or the thread ends. So the code that panicked never goes on, and a program can still recover from a bug in one part of its work:

```swift
catchPanic {
    handle(request)
} recover: { p in
    log("request failed: \(p.message)")      // the server goes on to the next request
}
```

A few failures can't unwind, and end the program at once instead ([below](#what-ends-the-program)).

## What panics

**The language and the runtime panic in the cases below, in every build unless noted, except where an `unchecked` block removes the check ([`unchecked` blocks](checks-and-build-modes.md#unchecked-blocks)).**

**Failures the code asks for:**

- `fatalError(…)`, `precondition(cond, …)`, `x!` on `nil`, `try!` on an error;
- `resumePanic(p)`, which carries on a panic already reported ([below](#resuming-a-panic-resumepanic));
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
- polling a task that has already finished ([07](../07-concurrency/tasks.md#semantics));
- making a channel with a `capacity` below 1, since a channel with no room could never take an item ([07](../07-concurrency/synchronization.md#queues-and-channels)).

**Conflicting uses:**

- conflicting accesses to a thread-bound object ([03](../03-handles-and-objects.md#dynamic-exclusivity)) or a thread-local ([07](../07-concurrency/global-state.md#thread-locals));
- destroying a thread-bound object while an access to it is live ([03](../03-handles-and-objects.md#destroying-an-object));
- taking a `Mutex`'s or an `RwLock`'s exclusive access on a thread that holds any access to it, or any access on a thread that holds its exclusive one, since that conflicts with a view the thread holds ([07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock));
- `lock()` on a `Slice` of a bare `Shared<Blob>`, since nothing writes a `Frozen` value ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers));
- overlapping calls on one side of a single-producer or single-consumer queue, so that its algorithm never sees two producers or two consumers at once ([07](../07-concurrency/synchronization.md#queues-and-channels));
- a thread joining its own `Thread`, since it would wait for itself for ever ([07](../07-concurrency/thread-work.md#joining-a-thread)).

**Running out:**

- a count kept for safety that would overflow:
    - the reader counts of an object, a thread-local and an `RwLock` ([03](../03-handles-and-objects.md#dynamic-exclusivity), [07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock));
    - pin counts ([03](../03-handles-and-objects.md#pinning-for-c));
    - a thread's counts of its uses of an allocator ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it));
    - the counts behind `Shared`, `LocalShared`, `Published` snapshots, and `Sender`, `Receiver`, `Promise` and `Future` values ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners), [07](../07-concurrency/synchronization.md#queues-and-channels));
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
- calling `rayo_init` a second time, and calling `rayo_thread_detach` or `rayo_shutdown` on a thread with a Rayo frame on any of its stacks, since those frames may still use what either call destroys ([08](../08-c-interop/c-contract-and-embedding.md#embedding-rayo-in-a-c-program));
- a wait during startup that would park with no timeout, since no other thread runs Rayo code during startup ([07](../07-concurrency/global-state.md#initialization-at-startup));
- a thread queued during startup that the platform can't start when startup ends, which panics on the startup thread as part of startup, so it ends the program ([07](../07-concurrency/thread-work.md#lent-work-and-queued-threads));
- `Thread.start`, `ThreadScope.spawn` and std's lending calls when `Runtime.startThread` refuses the start, which happens only outside startup ([07](../07-concurrency/thread-work.md#lent-work-and-queued-threads)).

**Poisoned locks.** `lock`, `read` and `write` on a lock that a panic has poisoned, until `clearPoison()` resets it ([07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock)).

**Names.** `Name(s)` panics when another text already has `s`'s hash, since no two texts share a `Name` ([04](../04-types/collections.md#collections-and-strings)).

### Messages

```swift
func fatalError(_ message: some Formattable) -> Never
func precondition(_ cond: Bool, _ message: some Formattable)
func precondition(_ cond: Bool)
func assert(_ cond: Bool, _ message: some Formattable)
func assert(_ cond: Bool)

fatalError("enemy \(id) has no mesh")      // an interpolated message, formatted only when it panics
```

**A panic's message is any `Formattable` value, such as a string or an interpolated literal** ([04](../04-types/collections.md#strings)).

**The message argument is evaluated only on the path that panics.** That is an exception to the order in which a call evaluates its arguments ([01](../01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)), and it holds only for these three:

- **When.** `fatalError` evaluates its message whenever it is called, and `precondition` and `assert` only once their condition is false. So the message never runs where the check passes, and can't panic there.
- **Only these builtins.** Each is builtin and never a function value, so every call of one is direct. No declaration can give a parameter this evaluation: a function that wraps one and takes a message evaluates its argument before the call, as any call does.
- **Only the argument.** A literal stored in a local first was evaluated at its declaration, as any initializer is.

**A check that doesn't run evaluates neither its condition nor its message** ([Checks and build modes](checks-and-build-modes.md#unchecked-blocks)).

**Each of these panics has a fixed text**, which stands in for the message where the message can't be shown:

- `fatalError` has `fatal error`, `precondition` has `precondition failed`, and `assert` has `assertion failed`, and `precondition(cond)` and `assert(cond)` panic with theirs as the whole message;
- each check the language makes panics with a text that names the check, such as `integer overflow`, `division by zero`, `index out of range` or `unwrapped nil`.

**The sinks a message goes to allocate nothing.** When the panic happens, the message is evaluated, then formatted once, straight into the platform's report sink and into the `Panic` a recovery point may catch ([below](#the-panic-value)). So reporting a panic allocates nothing, unless a segment's own `format` does.

**A panic while the message is evaluated or formatted is an ordinary panic.** The first panic is reported with its fixed text in place of the message, and the second, reported in turn, unwinds as any panic does. Since the message goes straight into the report sink, the first report may hold the part of the message written before the second panic, followed by the fixed text. So when `i` is out of range, `precondition(i < items.count, "bad index \(items[i].name)")` reports `precondition failed`, then unwinds with `index out of range`, which a recovery point catches.

## What a panic does

**A panic runs these steps on the thread that panicked:**

1. **It is reported** through the platform as it happens, whether or not a recovery point catches it later.
2. **It unwinds the thread**, one frame at a time, innermost first ([below](#unwinding)).
3. **It stops at the innermost recovery point** on the thread, whose `recover` closure then runs with it as a `Panic` ([below](#catching-a-panic-catchpanic)). With none, the unwind reaches the thread's first frame, and the thread ends ([below](#uncaught-panics)).

**The runtime reports panics one at a time, in one total order that respects happens-before.** A panic that happens before another is reported first. So a root cause comes before the panics that follow from it: a panic that poisons a lock is reported before the unwind poisons it, so before any panic of a thread that then finds the lock poisoned. Code that must pick one of several panics, such as a lending call, picks the first reported ([07](../07-concurrency/thread-work.md#panics-in-lent-work)).

### Unwinding

**Unwinding** is how a panic leaves the frames of its thread. It ends each frame as a `throw` that nothing catches would: it destroys each live value the frame owns and runs each live `defer` block, in the order a scope's end destroys them ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction-by-unwinding)). That covers the temporaries of the statement the panic interrupted, and a value that holds only some of its fields, which loses exactly those.

**Unwinding ends what each frame began, as a return would:**

- **Borrows and views** end with the frame, as the values that hold them are destroyed.
- **Dynamic accesses** release their marks once the unwind has destroyed the last value that depends on them ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). Opens of owning values stop counting as uses of their allocators the same way ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).
- **Property accesses** run no accessor code as they unwind. Changes made through a place property stay, and a value property's `set` isn't called, so it keeps its old value ([02](../02-views-and-dependencies/place-and-value-properties.md#panics-during-a-change)).

**Every point that can panic is an exit for the rules that check exits.** So an unwind never breaks a rule that a return keeps. Those points are the operations that [What panics](#what-panics) lists, and every call, since the callee may panic. A property's accessor is a call too: a `borrow`, a `mutate`, a `get` or a `set`. A place property's place is no such point, since its accessor has returned before the caller uses it.

**Two checks treat those points as exits:**

- a `defer` body is checked as if written at each of them too ([Cleanup](typed-errors.md#cleanup));
- a scoped `mutable` parameter counts as used at each of them, so a callee never leaves its caller a view of what it freed ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)).

**Each such point is checked as the unwind leaves it:**

- the borrows of the call have ended;
- the values the call took have left their places;
- what the call may have stored in its arguments is absorbed, as rule 4 adds after a call returns ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)).

```swift
defer { x.reset() }
f(&x)                  // fine: if f panics, its borrow of x has ended by the time the defer runs
```

**A panic in a `deinit` or a `defer` block unwinds as any panic does, except in code an unwind runs** ([below](#what-ends-the-program)). The unwind still destroys the rest of the value whose `deinit` panicked, its fields after its `deinit`, and every other live value. An assignment whose old value's `deinit` panics has already stored its new value ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction)).

### Uncaught panics

**A panic that no recovery point catches ends its thread.** The unwind destroys the thread's first frame too, and the thread's teardown then runs as when its body returns ([07](../07-concurrency/global-state.md#thread-teardown)). A library that started the thread or lent it work carries the panic on in the thread that waits for it: `join()` resumes it in the joiner ([07](../07-concurrency/thread-work.md#joining-a-thread)), and a lending call on the lending thread ([07](../07-concurrency/thread-work.md#panics-in-lent-work)).

**On the main thread, the program then shuts down as when `main` returns, and exits with status 101.** Shutdown runs the main thread's teardown and closes entry from C ([07](../07-concurrency/global-state.md#shutdown)).

## What ends the program

**These failures end the program at once, without unwinding:**

- **Running out of stack.** Unwinding runs `deinit`s and `defer` blocks, which need the stack that ran out. Each case is caught before anything is written past the stack's end:
    - a call, or the destruction of deeply nested values, that needs more of the stack it runs on than is left, a fiber's stack that C declared included;
    - a call into C made with less stack left than its target declares, or than `target.cStackReserve` when it declares nothing ([08](../08-c-interop/imports-and-inline-c.md#the-stack-a-c-call-needs)).
- **An allocation that fails in a plain form**, such as `UniquePointer(v)` or a closure context past the inline budget. Code that can recover uses a fallible form, which returns `nil` or fails with an error ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)).
- **A panic that would unwind out of code an unwind runs**, such as a `deinit` or a `defer` block ([above](#unwinding)). A recovery point catches one panic, and the thread would carry two.
- **A panic that would unwind out of a thread's teardown**, such as one in a thread-local's `deinit`, since no frame is left to unwind to ([07](../07-concurrency/global-state.md#thread-teardown)).
- **A panic that would unwind out of a thread-local's initializer on any thread outside startup**, since no joiner can learn of it ([07](../07-concurrency/global-state.md#thread-locals)). On a C thread that is attaching, it would unwind into C anyway, as the next item says.
- **A panic that would unwind into C**, out of any entry from C. That is a C entry, which is an `@export` or `@c` function or a closure literal converted to a `@c` type, or one of the runtime's C exports, such as `rayo_init`, `rayo_thread_attach`, `rayo_thread_detach` or `rayo_shutdown` ([08](../08-c-interop/c-contract-and-embedding.md#embedding-rayo-in-a-c-program)). C has no way to unwind its frames or run their cleanup ([08](../08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c)).
- **Every panic, under the abort strategy** ([below](#panic-strategy)).

**Ending the program runs these steps:**

- **The failure is reported.** A panic is reported when it happens, and any other failure as it ends the program. Once one failure is ending the program, a thread that fails or panics after it stops without reporting.
- **The program ends once the report is made.** No frame unwinds and no shutdown runs, so no `deinit` or `defer` block runs either.
- **Every other thread stops.** Where the platform can suspend threads, each stops where it stands, lent work included, so the report can show its stack as it was. Elsewhere, each stops the next time it enters Rayo from C or parks, or when the program ends, so a thread deep in a long computation may run briefly after the failure.

## Catching a panic: `catchPanic`

```swift
func catchPanic<R, EB: Error, ER: Error>(
    _ body: consuming () -> R!EB,
    recover: consuming (Panic) -> R!ER
) -> R!(EB | ER)

let frame = catchPanic {
    world.step()                              // may change anything it captures
    return world.snapshot()
} recover: { p in
    log("step failed: \(p.message)")
    world = loadWorld(level)                  // 'world' may be half-changed: this program rebuilds it
    return lastGoodFrame.clone()
}
```

**`catchPanic` runs its body, and runs `recover` only if a panic unwinds out of the body.** The call is a **recovery point**, where an unwind stops, and its value is an `R!(EB | ER)` either way, which is an `R` where neither closure can fail:

- **When the body returns**, `catchPanic` returns what it returned, and `recover` never runs.
- **When a panic unwinds out of the body**, the unwind stops once it has destroyed the body's frames and the body closure itself. Then `recover` runs with the panic as a `Panic` ([below](#the-panic-value)), and `catchPanic` returns what `recover` returns.
- **Errors pass through.** When either closure fails, `catchPanic` returns that failure, so a `try` on the call propagates it ([Results](typed-errors.md#results)). Where neither closure can fail, `EB` and `ER` are `Never`, so the call is an `R`, as `frame` is above ([What a failure type names](typed-errors.md#what-a-failure-type-names)). An `R` that itself holds an error is returned as any value is. A panic is never an error, and no `catch` sees one.

**After a caught panic, what the body was changing may be half-changed.** The unwind stops the body wherever it panicked. So each place the body changed holds a valid value, but not always the one the body meant to leave there. `recover` sees those places as the unwind left them, so it is where the code checks or repairs them, or decides to leave them. That is why `recover` is required: an empty one, as in `recover: { _ in }` for a `Void` body, is a visible choice.

**The two closures' captures don't conflict with each other, since the closures never run at once.** `recover` runs only after the unwind has destroyed the body closure. So both may capture one place, exclusively too, as both capture `world` above. That exception to the law of exclusivity ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)) is narrow:

- it covers only two closure literals written as `catchPanic`'s arguments, never function values made before the call;
- it covers only the conflict between those two closures' captures;
- everything else is checked as usual. A value that the body closure's creation made depend on a place still conflicts with `recover`'s use of that place ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)).

```swift
catchPanic {
    views.append(name.view)          // creating this closure makes 'views' depend on 'name'
} recover: { _ in
    name = String("b")               // error: 'views' depends on 'name', and is used below
}
print(views[0])
```

Moves are checked as for any call's arguments: a place that either closure owns a capture of moved into it when the call began, so the other can't use it. Whether a captured place holds a value is tracked across both closures ([01](../01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)).

- **Each closure runs at most once**, the body exactly once. Both parameters are `consuming`, so either closure may move out of what it owns, and a closure of any kind is accepted ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)).
- **The innermost one catches.** A panic unwinds to the innermost `catchPanic` on its own thread, and a panic on another thread never reaches it.
- **A panic in `recover`** unwinds as any panic does, to the next recovery point out. `recover` isn't code an unwind runs, since the first unwind has ended when it starts.
- **Catching undoes nothing.** The report was made when the panic happened, and the values the unwind destroyed stay destroyed.
- **Not at compile time.** A panic during compile-time evaluation is a compile error, and `catchPanic` can't run there ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)). The error shows the panic's message where compile-time evaluation can evaluate it, and its fixed text otherwise ([above](#messages)).
- **Not under the abort strategy**, where a panic ends the program before it can reach a recovery point ([below](#panic-strategy)).

### The `Panic` value

```swift
struct Panic {                 // copyable and Sendable: up to 256 bytes of its message, inline
    let sequence: UInt64       // its place in the runtime's report order
    …
}
struct SourceLocation(let file: StaticString, let line: Int, let column: Int)
```

**A `Panic` keeps a copy of its message, since the unwind destroys what the message's segments borrowed:**

- **`p.message`** is a `StringView` of that copy, which `p` holds in a 256-byte buffer of its own. A longer message is cut at the last Unicode scalar boundary that fits, so the copy stays whole UTF-8 ([04](../04-types/collections.md#strings)).
- **`p.isCut`** is `true` when the message was cut, which tells a cut message from a whole one. The report always has the whole message.
- **`p.location`** is where the panic happened: the call to `fatalError`, `precondition` or `assert`, or the operation whose check failed.

**`p.sequence` is unique to the panic, and increases in the runtime's report order** ([above](#what-a-panic-does)). So of two panics `a` and `b`, `a` was reported first exactly when `a.sequence < b.sequence`. Code that picks one of several panics, as a lending call does, uses it to pick the first reported.

**Only the runtime makes a `Panic`.** The type has no public initializer, so every `Panic` that code holds, and every panic that `resumePanic` carries on, was reported when it happened.

**A `Panic` is copyable and `Sendable`, and making one allocates nothing**, since everything it holds is inline. So one thread can hand another the panic it caught ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).

### Resuming a panic: `resumePanic`

```swift
func resumePanic(_ p: Panic) -> Never
```

**`resumePanic(p)` unwinds the thread with a caught panic, as if it had never been caught.** It doesn't report `p` again, and keeps its message, location and sequence, so a later recovery point catches the panic as it first happened.

**A library that lends work to other threads carries a piece's panic back with it.** Each piece runs under `catchPanic`, and keeps its panic, if any, in a slot of its own. Once all the work has finished, the library hands the slots back to the lending thread, which resumes a panic it finds ([07](../07-concurrency/thread-work.md#panics-in-lent-work)):

```swift
let caught: Panic? = catchPanic { piece(); return nil } recover: { p in copy p }   // on a worker: this piece's slot
...                                                                                // the library waits for every piece
if let p = caught { resumePanic(p) }                                               // on the lending thread: carry it on
```

## Panic strategy

**The panic strategy says how a panic ends: by unwinding, the default, or by aborting.** A build chooses it with its other settings ([09](../09-compile-time/attributes-and-runtime-data.md#what-a-build-declares)). Under the **abort** strategy, every panic is reported, then ends the program at once through the platform's abort, as the failures above do ([above](#what-ends-the-program)). So `catchPanic` never catches: it runs its body, and never its `recover` closure.

**The compile-time rules are the same under both strategies.** `catchPanic` still takes its `recover` closure, which is checked as written, and every point that can panic still counts as an exit ([above](#unwinding)). So a library compiles the same whichever strategy the program uses.

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
