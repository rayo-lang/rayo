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
do {
    try catchPanic { handle(request) }
} catch let p as Panic {
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

**Poisoned locks.** An unwind out of a lock's exclusive access, through a guard or a closure, poisons the lock: a `Mutex`'s access does, and an `RwLock`'s `write` access does, but its `read` access doesn't. Then `lock`, `read` and `write` on it panic until `clearPoison()` resets it, so no code takes what the panic left half-changed for a whole value ([07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock)).

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

- `fatalError` has `fatal error`, `precondition` has `precondition failed`, and `assert` has `assertion failed`, which are also the whole message of the forms that take none;
- each check the language makes panics with a text that names the check, such as `integer overflow`, `division by zero`, `index out of range` or `unwrapped nil`.

**The sinks a message goes to allocate nothing.** When the panic happens, the message is evaluated, then formatted once, straight into the platform's report sink and into the `Panic` a recovery point may catch ([below](#the-panic-value)). So reporting a panic allocates nothing, unless a segment's own `format` does.

**A panic while the message is evaluated or formatted is an ordinary panic.** The first panic is reported with its fixed text in place of the message, and the second, reported in turn, unwinds as any panic does. So when `i` is out of range, `precondition(i < items.count, "bad index \(items[i].name)")` reports `precondition failed`, then unwinds with `index out of range`, which a recovery point catches.

## What a panic does

**A panic runs these steps on the thread that panicked:**

1. **It is reported** through the platform as it happens, whether or not a recovery point catches it later.
2. **It unwinds the thread**, one frame at a time, innermost first ([below](#unwinding)).
3. **It stops at the innermost recovery point** on the thread, which throws it as a `Panic` error ([below](#catching-a-panic-catchpanic)). With none, the unwind reaches the thread's first frame, and the thread ends ([below](#uncaught-panics)).

### Unwinding

**Unwinding** is how a panic leaves the frames of its thread. It ends each frame as a `throw` that nothing catches would: it destroys each live value the frame owns and runs each live `defer` block, in the order a scope's end destroys them ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction-by-unwinding)). That covers the temporaries of the statement the panic interrupted, and a value that holds only some of its fields, which loses exactly those.

**Unwinding ends what each frame began, as a return would:**

- **Borrows and views** end with the frame, as the values that hold them are destroyed.
- **Dynamic accesses** release their marks once the unwind has destroyed the last value that depends on them ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). Opens of owning values stop counting as uses of their allocators the same way ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).
- **Accessors** run no code after their `yield`, and no `set` is called. An unwind out of an access through a property or a subscript runs only the accessor frame's `defer` blocks and its locals' `deinit`s, as for any frame. It unwinds that frame once it has destroyed the last value that depends on the `yield`. A value that a `get` made for a `set` is destroyed.

**Every point that can panic is an exit for the rules that check exits.** So an unwind never breaks a rule that a return keeps. Those points are these:

- the operations that [What panics](#what-panics) lists;
- every call, since the callee may panic;
- each `yield`, where the caller's panic may end the accessor.

**Two checks treat those points as exits:**

- a `defer` body is checked as if written at each of them too ([Cleanup](typed-errors.md#cleanup));
- a scoped `mutable` parameter counts as used at each of them, so a callee never leaves its caller a view of what it freed ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)).

**Each such point is checked as the unwind leaves it:**

- the borrows of the call, or what the `yield` lends, have ended;
- the values the call took have left their places;
- what the call may have stored in its arguments is absorbed, as rule 4 adds after a call returns ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)).

```swift
defer { x.reset() }
f(&x)                  // fine: if f panics, its borrow of x has ended by the time the defer runs
```

**A panic in a `deinit` or a `defer` block unwinds as any panic does, except in code an unwind runs** ([below](#what-ends-the-program)). The unwind still destroys the rest of the value whose `deinit` panicked, its fields after its `deinit`, and every other live value. An assignment whose old value's `deinit` panics has already stored its new value ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction)).

### Uncaught panics

**A panic that no recovery point catches ends its thread.** The unwind destroys the thread's first frame too, and the thread's teardown then runs as when its body returns ([07](../07-concurrency/global-state.md#thread-teardown)). How the end of a thread reaches the code that started it or lent it work is in 07 ([07](../07-concurrency/thread-work.md#lending-work-and-starting-threads)).

**On the main thread, the program then shuts down as when `main` returns, and exits with status 101.** Shutdown runs the main thread's teardown and closes entry from C ([07](../07-concurrency/global-state.md#shutdown)).

## What ends the program

**These failures end the program at once, without unwinding:**

- **Running out of stack.** Unwinding runs `deinit`s and `defer` blocks, which need the stack that ran out. Each case is caught before anything is written past the stack's end:
    - a call, or the destruction of deeply nested values, that needs more of the stack it runs on than is left, a fiber's stack that C declared included;
    - a call into C made with less stack left than its target declares, or than `target.cStackReserve` when it declares nothing ([08](../08-c-interop/imports-and-inline-c.md#the-stack-a-c-call-needs)).
- **An allocation that fails in a plain form**, such as `UniquePointer(v)` or a closure context past the inline budget. Code that can recover uses a fallible form, which returns `nil` or throws ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)).
- **A panic that would unwind out of code an unwind runs**, such as a `deinit` or a `defer` block ([above](#unwinding)). A recovery point catches one panic, and the thread would carry two.
- **A panic that would unwind out of a thread's teardown**, such as one in a thread-local's `deinit`, since no frame is left to unwind to ([07](../07-concurrency/global-state.md#thread-teardown)).
- **A panic that would unwind into C**: out of an `@export` or `@c` function, or a closure literal converted to a `@c` type. C has no way to unwind its frames or run their cleanup ([08](../08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c)).
- **Every panic, under the abort strategy** ([below](#panic-strategy)).

**Ending the program runs these steps:**

- **The failure is reported.** A panic is reported when it happens, and any other failure as it ends the program. Once one failure is ending the program, a thread that fails or panics after it stops without reporting.
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
- **Not at compile time.** A panic during compile-time evaluation is a compile error, and `catchPanic` can't run there ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)). The error shows the panic's message where compile-time evaluation can evaluate it, and its fixed text otherwise ([above](#messages)).
- **Not under the abort strategy**, where a panic ends the program before it can reach a recovery point ([below](#panic-strategy)).

### The `Panic` value

```swift
struct Panic: Error { … }      // copyable and Sendable: up to 256 bytes of its message, inline
struct SourceLocation(let file: StaticString, let line: Int, let column: Int)
```

**A `Panic` keeps a copy of its message, since the unwind destroys what the message's segments borrowed:**

- **`p.message`** is a `StringView` of that copy, which `p` holds in a 256-byte buffer of its own. A longer message is cut at the last Unicode scalar boundary that fits, so the copy stays whole UTF-8 ([04](../04-types/collections.md#strings)).
- **`p.isCut`** is `true` when the message was cut, which tells a cut message from a whole one. The report always has the whole message.
- **`p.location`** is where the panic happened: the call to `fatalError`, `precondition` or `assert`, or the operation whose check failed.

**Only the runtime makes a `Panic`.** The type has no public initializer, so every `Panic` that code holds, and every panic that `resumePanic` carries on, was reported when it happened.

**A `Panic` is copyable and `Sendable`, and making one allocates nothing**, since everything it holds is inline. So one thread can hand another the panic it caught ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).

### Resuming a panic: `resumePanic`

```swift
func resumePanic(_ p: Panic) -> Never
```

**`resumePanic(p)` unwinds the thread with a caught panic, as if it had never been caught.** It doesn't report `p` again, and keeps its message and location, so a later recovery point catches the panic as it first happened. A library that runs work on other threads uses it to carry that work's panic to the thread that waits for it ([07](../07-concurrency/thread-work.md#lending-work-to-other-threads)).

### What the closure may change

**`catchPanic`'s closure may reach nothing that a panic could leave half-changed for the code after the recovery point.** So, unless the capture is marked `unwindSafe` ([below](#marking-a-capture-unwindsafe)), the closure may not:

- depend on a place exclusively, by capturing it exclusively ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)) or by holding an exclusive view of it, such as a `MutableSpan` ([02](../02-views-and-dependencies/dependency-projection-and-results.md#mutable-views));
- capture a value whose type holds, at any depth, an object owner, a weak pointer or a `Slice`, since an object's value and a slice's locked buffer change through a shared path ([03](../03-handles-and-objects.md#dynamic-exclusivity), [06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)).

**A capture whose type may hold one counts as holding one.** Those are a type parameter, an `any P` and a function value, whose types don't show what they hold.

```swift
do {
    try catchPanic { world.step(dt) }                          // error: the closure captures 'world' exclusively
} catch let p as Panic { log("step failed: \(p.message)") }

let drawn = try? catchPanic { renderer.value?.submit(mesh) }   // error: 'renderer' is a weak pointer to an object
```

**The rule guards what code sees, not memory safety.** A value that a panic interrupts in safe code is still a valid value of its type, and `unsafe` code keeps it one ([Unsafe code](unsafe-code.md#panics-in-unsafe-code)). So `unwindSafe` needs no `unsafe`.

**Thread-locals, globals and `Synchronized` values are outside the rule.** A closure reaches a thread-local or a global without capturing it ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)), so the rule can't see one, and code after the recovery point checks those itself. A closure may capture a `Synchronized` value, since a lock that a panic may have left half-changed is poisoned ([above](#what-panics)), and each atomic operation is whole.

### Marking a capture `unwindSafe`

**`unwindSafe` in the closure's capture list lifts the rule for one capture.** The caller then takes on what the rule checks: that the code after the recovery point copes with whatever the panic left there. It marks a capture in one of these forms:

- `[unwindSafe &world]` captures `world` by exclusive reference, and `[unwindSafe world]` by shared reference, each the whole place, used only as that capture allows ([05](../05-protocols-generics-and-closures/functions-and-closures.md#capturing-places));
- `[unwindSafe move rows]` and `[unwindSafe copy body]` capture as `[move rows]` and `[copy body]` do.

`unwindSafe` appears only in a closure literal written as `catchPanic`'s argument.

```swift
do {
    try catchPanic { [unwindSafe &world] in world.step(dt) }   // fine: the caller vouches for 'world'
} catch let p as Panic {
    world.resetPhysics()                                       // and repairs what the panic may have left
}
```

**A function that passes a function value on to `catchPanic` marks it, and the mark vouches for every caller whose function value passes through.** Taking a non-`mutating` function, as `guarded` does, keeps any caller from passing one that changes the caller's places exclusively. What `guarded` vouches for is what those closures change through a shared path:

```swift
func guarded(_ body: () -> Void) {
    do {
        try catchPanic { [unwindSafe copy body] in body() }    // vouches for every caller's 'body'
    } catch let p as Panic { log("guarded work failed: \(p.message)") }
}
```

## Panic strategy

**The panic strategy says how a panic ends: by unwinding, the default, or by aborting.** A build chooses it with its other settings ([09](../09-compile-time/attributes-and-runtime-data.md#what-a-build-declares)). Under the **abort** strategy, every panic is reported, then ends the program at once through the platform's abort, as the failures above do ([above](#what-ends-the-program)). So `catchPanic` never catches: it calls its closure, and returns or throws what the closure does.

**The compile-time rules are the same under both strategies.** The rule on `catchPanic`'s closure applies, and every point that can panic still counts as an exit ([above](#unwinding)). So a library compiles the same whichever strategy the program uses.

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
