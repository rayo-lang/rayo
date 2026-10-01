# 08 · Grace periods and checkpoints

## Grace periods: how deferred memory is reclaimed

Some safe operations make memory unreachable while a view, on any thread, may still be reading it: resetting an arena, unregistering an allocator, and publishing a new `Published` value. A value destroyed, or memory made unreachable, while something may still use it is **retired** instead of freed: its `deinit`s and its release wait until nothing can still see it. For a thread-bound object, that is its own thread's accesses and pins ([03](03-handles-and-objects.md#destroying-an-object)). A thread is **inside a section** while it runs Rayo code that might hold a view.

**Retired memory that a view may still be reading is reclaimed only after every thread has been outside a section at some moment since it was retired. That span is a grace period.** Outside exit, no thread waits for another to reclaim memory ([below](#at-exit-reclaim-then-close-entry)).

No view of memory that a grace period can free outlives the section it was made in. A view that borrows memory that can be freed is scoped ([02](02-views-and-dependencies.md#scoped-values)), and no borrow is live across a checkpoint, where a long-lived thread leaves its section ([below](#checkpoints-and-parking-waits)), except the places that a qualifying wait or entry call borrows, which the path rule keeps where no grace period frees them ([below](#what-a-wait-may-borrow)). So no thread can still see memory after its grace period.

### Sections

A section begins when:

- C, at depth zero, calls an `@export` or `@c` function, or a closure literal converted to a `@c` pointer, attaching the thread on first entry;
- an entry body ([below](#where-a-checkpoint-can-go)) is entered from depth zero: the program's `main`, or the body of a thread started with `Runtime.startThread` ([07](07-concurrency.md#starting-a-thread-runtimestartthread));
- a thread's copies of its thread-locals are initialized, or its **teardown** runs, which destroys them and the thread's objects and runs the `deinit`s queued to it ([07](07-concurrency.md#global-state)). Each runs in a section entered from depth zero, as a call from C does, except that a `Runtime.startThread` thread initializes inside its body's section, before the body, and the startup thread inside startup's, interleaved with the globals. Before startup has finished or after shutdown, such an entry fails as that thread's entry would: a C thread's panics ([07](07-concurrency.md#initialization-at-startup)), and a `Runtime.startThread` thread parks for good ([07](07-concurrency.md#starting-a-thread-runtimestartthread));
- the reclaimer runs retired values' `deinit`s or hands memory back through the `AllocatorImpl` hooks ([06](06-memory-and-allocators.md#writing-an-allocator-allocatorimpl)) on its runtime thread, or on the exiting thread at exit. A `Runtime.reclaim` call does the same inside its caller's section, and begins none;
- startup runs global initializers ([07](07-concurrency.md#initialization-at-startup));
- a checkpoint ends. A wait that is a checkpoint re-enters when the thread wakes, before it reads anything the wait borrows, and while parked it touches only the word it parks on.

A section ends when the code that began it returns to depth zero, or at a checkpoint that takes effect.

**Entries nest.** A thread outside Rayo is at depth zero, and entering a section makes it one. The depth is the thread's, whatever stack its code runs on, so a Rayo frame that a fiber switch suspended still counts ([09](09-c-interop.md#what-c-must-uphold)), and a call that leaves the section at a checkpoint, as a `parks` C call does ([09](09-c-interop.md#blocking-c-calls-parks)), puts the thread at depth zero until it returns:

```swift
func main() {                                        // entered at depth zero: the section begins, at depth one
    while !shouldQuit() {
        unsafe { phys_step(scene, dt, onContact) }   // C middleware, which calls onContact during the step
        checkpoint                                   // at depth one: takes effect
    }
}

@c func onContact(_ a: UInt64, _ b: UInt64) {        // runs at depth two: main's frame below may hold views
    queueContact(a, b)                               // a checkpoint here would do nothing
}
```

Three kinds of call run one depth deeper, since outer Rayo frames may still hold views: a C entry called from Rayo, directly, through a function value or through a `@c` pointer, Rayo called back from C that Rayo called, as `onContact` is, unless that C call left the section, and a call through an entry function value that doesn't qualify ([below](#entry-function-types)). Returning from a deeper call leaves no section, and a checkpoint takes effect only at depth one, so it never releases views held by frames below it.

**A parking wait runs no other code of its section while parked**: a `@parks` function touches only its park word then ([below](#writing-a-parking-wait-the-parks-promise)), a callback that a `parks` C call makes meanwhile runs in a section of its own ([09](09-c-interop.md#blocking-c-calls-parks)), and a wait that is a checkpoint runs only the thread's queued `deinit`s when it re-enters ([below](#deinits-queued-to-a-thread)). Work that a job system runs on a thread waiting in its join has no checkpoint that takes effect: a closure that isn't an entry body can't hold one, and a call through an entry function value that doesn't qualify runs one depth deeper ([below](#entry-function-types)).

**Lent work** runs inside the running thread's own section. What keeps the lent work's views safe is the lending thread's section, open until the work is done ([07](07-concurrency.md#the-librarys-promise)).

**Entering and leaving a section never waits** for another thread, and takes no lock, except that an entry after shutdown panics or parks for good ([below](#at-exit-reclaim-then-close-entry)). The queued `deinit`s that an outermost entry runs ([below](#deinits-queued-to-a-thread)) are ordinary code, which may do either.

### Who reclaims, and when

**The reclaimer runs retired values' `deinit`s and returns memory to allocators.** Besides it, only these threads run a retired or queued value's `deinit`:

- a thread destroying an object through its owner while no access or pin holds it ([03](03-handles-and-objects.md#destroying-an-object));
- a thread in its teardown, which destroys the objects it still has ([07](07-concurrency.md#global-state));
- a creating thread whose new object a reset or an unregistration destroyed while it was being created ([03](03-handles-and-objects.md#objects-in-arenas-and-other-allocators));
- a thread that `deinit`s were queued to ([below](#deinits-queued-to-a-thread)): a thread-bound object's home thread, and the thread that retired a pinned value that isn't `Sendable` ([03](03-handles-and-objects.md#pinning-for-c));
- a thread that drops the last `Shared` snapshot of a retired `Published` value after its grace period ([07](07-concurrency.md#snapshots-one-time-values-and-waits)).

**The reclaimer** is a runtime thread, which the runtime may start when startup ends, or a thread that calls `Runtime.reclaim(budget:)`. Whether the runtime thread exists, and how often it wakes, is runtime policy; where it exists, it keeps reclaiming while memory whose grace period has passed is pending. `Runtime.reclaim(budget:)` reclaims what is ready on the calling thread for up to `budget` of time, whether or not a runtime thread exists, and never waits for a grace period. At exit, the exiting thread is the reclaimer ([below](#at-exit-reclaim-then-close-entry)).

**The `deinit`s given to the reclaimer run on the reclaiming thread**: a retired `Published` value that no snapshot holds, a pinned `Sendable` value that isn't a thread-bound object's, and an unregistered allocator's implementation once its waits pass ([06](06-memory-and-allocators.md#unregistering-an-allocator)). A thread-bound object's `deinit`, and those of other values that aren't `Sendable`, are queued to their own thread instead. A `deinit` that touches a `@threadlocal var` sees the reclaiming thread's copy.

### Deinits queued to a thread

Some `deinit`s must run on one thread: a thread-bound object's that was destroyed under a live access or a pin, or retired by a reset or an unregistration ([03](03-handles-and-objects.md#destroying-an-object)), and a pinned value's that isn't `Sendable` ([03](03-handles-and-objects.md#pinning-for-c)). **Such a `deinit` is queued to its thread, which runs it at its next outermost section entry once no pin holds the value** ([03](03-handles-and-objects.md#destroying-an-object)), including the one right after a checkpoint, before any other code of that section, or in its teardown ([07](07-concurrency.md#global-state)).

None of that thread's views or accesses is live there except borrows of places that meet the path rule ([below](#what-a-wait-may-borrow)), such as those a qualifying wait keeps. The only Rayo frames below an outermost entry are those that left the section at a checkpoint, a `parks` C call included, and a checkpoint goes only where no borrow or dynamic access is live but those ([below](#where-a-checkpoint-can-go)): places in a global, which a `deinit` reaches only through a shared borrow, its own synchronization or a thread-local's mark, and places in an entry body's own storage, which no `deinit` can name. So the `deinit` never runs under code that holds what it destroys, and a worker that waits for work at a checkpoint runs its queued `deinit`s before each piece of work it picks up.

### At exit: reclaim, then close entry

The runtime shuts down when `main` returns, or when a C program that embeds Rayo calls `rayo_shutdown()` ([09](09-c-interop.md#the-platform-and-embedding-rayo-in-c)). **At exit, on the exiting thread:**

1. Retired memory is reclaimed while the thread's thread-locals are still live, so a `deinit` that flushes or closes something runs, and sees that thread's copies, the current allocator included.
2. The thread tears down, reclaiming what its teardown retires ([07](07-concurrency.md#global-state)).
3. Entry closes, and the runtime's reclaimer thread, where there is one, ends. An entry from C with no Rayo frame below it on its thread panics ([07](07-concurrency.md#initialization-at-startup)), and any other attempt to begin a section parks its thread forever: a thread started with `Runtime.startThread`, or a thread inside Rayo code that has passed a checkpoint, a callback during a `parks` C call included.

The sequence has a time limit, which is runtime policy. Whatever the limit cuts short, because a thread stayed inside a section, is leaked, never destroyed under a reader, and so is a value that a pin still holds, whose `deinit` never runs.

**No global is destroyed**, not even at exit, since a thread still attached or inside a section may read one after entry closes; only a thread-local's copies end, each in its own thread's teardown ([07](07-concurrency.md#global-state)).

## Checkpoints and parking waits

A thread that runs Rayo code for its whole life, such as a worker or a program's main loop, never returns from the call that began its section, so it would delay reclamation forever. A long-lived body leaves its section between units of work with a `checkpoint` statement:

```swift
Thread.start(name: "navmesh") { [move input, move done] in    // done: Sender<NavMesh>
    var bake = NavMeshBake(consume input)
    while !bake.isDone {
        bake.step(budget: 2.ms)            // views live only inside step()
        checkpoint                         // leaves the section; retired memory can be reclaimed
    }
    done.push(bake.finish())
}
```

**The compiler checks that no borrow and no dynamic access is live across a checkpoint**, counting borrows as across an `await` ([07](07-concurrency.md#semantics)), except a borrow of a place of unscoped type that meets the path rule ([below](#what-a-wait-may-borrow)), held by a binding or worked out by the statement: the entry body's own storage never moves, a global is never freed, and an owning value reached through either is checked again at its next open ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)).

```swift
while !bake.isDone {
    let cells = bake.openCells.span        // a view into 'bake'
    let first = bake.openCells[0]          // a borrow of an element in the list's buffer
    checkpoint                             // error: 'cells' and 'first' are live across the checkpoint
    refine(cells)
    log(first)
}
```

A borrow of an element lies in an owning value's buffer, which was checked before the checkpoint, and a grace period that passes during the checkpoint may let an arena reuse that buffer. Owned locals may be live across a checkpoint: each later access to their storage opens the value again, which checks it again ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)).

**Calls that count as checkpoints**, under the same check, are a call to an `@entry` function ([below](#loops-owned-by-libraries-entry-functions)), a qualifying call through an entry function value ([below](#entry-function-types)), and a qualifying parking wait ([below](#blocking-waits)).

### Where a checkpoint can go

A checkpoint lets the reclaimer release memory that views pointed at, so it must never run while a Rayo frame below it may hold a view. **A `checkpoint` may appear only at the top level of an entry body.** An **entry body** is one of:

- `main`, which takes no parameters, returns `Void`, `Never`, or an `Int32` that becomes the process's exit status, and can't be called from Rayo code or made into a function value;
- an `@entry` function ([below](#loops-owned-by-libraries-entry-functions));
- a **C entry**, called from C ([09](09-c-interop.md)): an `@export` or `@c` function, or a closure literal converted to a `@c` pointer;
- an **entry literal**: a closure literal checked against an **entry function type** ([below](#entry-function-types)), however it is held afterwards, in a `Closure<… @entry …>` included.

The **top level** is the body's own statements, at any depth of blocks, `if`s, `when`s and loops, but not inside a nested function, a local type's or extension's members, or a closure literal that isn't itself an entry body. A call counts as placed there when it is part of such a statement, even nested in its expressions, as `draw(snapshots.waitPop())` is, and what the statement has already evaluated when the call runs counts as live across it, under the exception above.

**A C entry** that C calls at depth zero enters a section, so its checkpoints take effect: a callback on a thread a C library created, such as a middleware worker or an audio thread, or the start routine of a thread created through the C API. Reached from Rayo, it runs one depth deeper, where its checkpoints do nothing ([above](#sections)). So it carries no checkpoint into Rayo callers, and a named one converts to any function type its signature matches. Its `mutable` parameters stand for places C lent it, which may lie in memory a grace period frees, so each counts as a borrow for the checkpoint check, as an `@entry` function's borrowed parameter would ([below](#loops-owned-by-libraries-entry-functions)): none is used after a checkpoint, or after a wait or entry call that counts as one.

### Loops owned by libraries: `@entry` functions

An engine's `run()`, or a server library's `eventLoop()`, owns the loop, so its checkpoints are inside library code:

```swift
extension Engine {
    @entry consuming func run() -> Never {         // an engine library's main loop
        while true {
            frame()                                // views live only inside frame()
            checkpoint
        }
    }
}
func main() { Engine(loadConfig()).run() }         // allowed: called where a checkpoint could go
func restart() { Engine(loadConfig()).run() }      // error: 'restart' isn't an entry body
```

**An `@entry` function may contain checkpoints at its top level, and may be called only where a `checkpoint` could appear.**

- **Each parameter, `self` included, is `owned`, or of unscoped type and given at each call a place that meets the path rule** ([below](#what-a-wait-may-borrow)), as a wait's receiver is. Any other borrowed parameter or `self` could point into memory that a checkpoint lets the reclaimer reuse. Inside the body such a parameter counts as a place that meets the path rule, so `@entry mutating func run()` on an engine in a local of the entry body may keep `self` across its checkpoints.
- **A C entry is never `@entry`.** It is an entry body already, and Rayo calls it one depth deeper ([above](#where-a-checkpoint-can-go)), so the mark would only forbid conversions that are safe for it.
- **Its body runs within its call.** So a `task func`, whose body runs in its owner's later steps, and an accessor, whose code after the `yield` runs where the caller's access ends, are never `@entry`.
- **Callers always see the checkpoint.** It is called directly by name, through a value of an entry function type or a `Closure<… @entry …>` (next), or as the witness of a requirement declared `@entry`, whose calls in generic code are `@entry` calls too. It can't become any other function value or witness a requirement that isn't `@entry`, which would hide a checkpoint from its caller.

### Entry function types

A thread library takes the bodies it runs as function values, and those need checkpoints too. **An entry function type is a function type marked `@entry`**, whose parameters are owned, or unscoped and given places that meet the path rule, as an `@entry` function's are.

An **entry function value** is a value of an entry function type, a `Closure<… @entry …>`, or a value of an entry literal's concrete type. **A call through one is a checkpoint in its caller when:**

1. it is placed where a `checkpoint` could go;
2. the callee is a `Closure<… @entry …>` or an owned value of an entry literal's concrete type, which owns its closure;
3. the callee meets the path rule for a wait's receiver ([below](#what-a-wait-may-borrow)), since it stays borrowed across the call;
4. the call passes the checkpoint check ([above](#checkpoints-and-parking-waits)) for everything but the callee.

`var body = pending.removeFirst(); body()` qualifies. A call that fails any of these conditions runs the body one depth deeper, where its checkpoints do nothing: `bodies[i]()`, whose inline captures lie in a buffer that could be reused while the body is parked, or a call through a plain `@entry () -> Void` value, a view of closure storage that could lie anywhere.

- **Conversions.** A function value converts to an entry function type whose parameters match, since having no checkpoint is always allowed. An entry function value converts only to entry function types, by the conversions function values have, never to a function type without `@entry`. Into a `Closure<… @entry …>` move only an entry literal, an owned value of one's concrete type and a named function or operator, as [05](05-protocols-generics-and-closures.md#implicit-conversions) says.
- **An entry literal keeps its kind.** However an entry literal ([above](#where-a-checkpoint-can-go)) is held, by value as `some @entry () -> Void`, in a local of its own type, or as a generic argument, its concrete type satisfies and converts to entry function types and `Closure<… @entry …>` only, as a `consuming` literal's does to `consuming` types ([05](05-protocols-generics-and-closures.md#closure-kinds)). A constraint such as `F: () -> Void` rejects it, so every call to an entry literal is a call through an entry function value.

### Blocking waits

A wait can be a checkpoint, so a worker waiting for work doesn't delay reclamation while it blocks.

`draw(snapshots.waitPop())` in the renderer of [07](07-concurrency.md#work-that-outlives-the-caller-threads) is one, since `snapshots` is a global. A wait in a loop over a borrowed collection isn't:

```swift
Thread.start(name: "upload") { [move batch] in
    for item in batch { upload(item); done.wait() }      // just blocks: the loop borrows 'batch' across the wait ('done' is a global Event)
}
```

**A call to a parking wait placed where a `checkpoint` could go is a checkpoint automatically when it passes that check for everything but the places the wait itself borrows, and, for a `@parks` function, those places meet the path rule ([below](#what-a-wait-may-borrow)).** A **parking wait** is a function declared `@parks`, as std's `waitPop()`, `Event.wait()`, `Future.wait()` and `Thread.sleep` are, or a C function declared `parks`, in an import config or on an `extern c func`, such as `epoll_wait`. A C `parks` call needs the check and, for the place a `mutable` argument keeps borrowed, the path rule, while what its other arguments point at is the calling `unsafe` code's promise ([09](09-c-interop.md#blocking-c-calls-parks)).

**Otherwise a wait just blocks**, holding its section, as `done.wait()` above does, and as waits anywhere else do.

**A call through a requirement, a function value or an `any P` is a parking wait only as its caller sees it.** A requirement declared `@parks`, which any function may witness, is a parking wait wherever it is called, generic code included, where the check runs once at the definition ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). A `@parks` function called through any other requirement, through a function value or through an `any P` is an ordinary call there, so its park just blocks.

### What a wait may borrow

A thread parked at a checkpoint holds no section, so what it reads when it wakes must lie somewhere nothing can release while it sleeps:

```swift
Thread.start(name: "worker") { [move inbox] in           // inbox: List<Receiver<Job>>
    perform(inbox[0].waitPop())                          // just blocks: the receiver lies in the list's buffer
    var rx = inbox.removeFirst()                         // now a local owns the receiver
    while true { perform(rx.waitPop()) }                 // each wait is a checkpoint
}
```

**What a `@parks` wait borrows** stays borrowed across the checkpoint: its receiver, each borrowed or `mutable` argument, and the places a lock guard it consumes depends on, since no other scoped argument qualifies (below). **The call is a checkpoint only when each of those places lives in a global, a thread-local included, or in the entry body's own storage**: a local, owned parameter (`self` included) or owned capture of the entry body, or a stored field, inline array element or enum payload reached from one of those through stored fields, inline array elements and enum payloads only, with no projection on the way, as `if var r = &rx { r.waitPop() }` reaches an owned local `rx: Receiver<Job>?`. This is the **path rule**. A thread-local's dynamic access is then held across the checkpoint, so a queued `deinit` that reaches it panics.

- **Qualifying.** `snapshots.waitPop()` on a global, `rx.waitPop()` on an owned `Receiver`, `f.wait()` on an owned `Future`, and `self.inbox.waitPop()` in an `@entry consuming func run()`.
- **A local qualifies when it owns its value.** That is a `let` or `var` of a value, such as a call result, a literal or `consume x`, or one declared `owned` ([01](01-values-and-ownership.md#bindings)), destructured ones included, as in `var (tx, rx) = Channel<Job>.make(capacity: 64)`. A binding of a place, a `var` of `&place` or a pattern binding included, qualifies only when that place does, as `var r = &rx` does for an owned local `rx`. So `let f = futures[0]` and a `for` binding of an element that lives in the collection ([01](01-values-and-ownership.md#bindings)) don't: they name storage in someone else's buffer, which could be arena memory or an object's value.
- **Not qualifying.** A scoped receiver or argument, such as a span, which may view an arena's buffer; a place reached through an owning value's storage, even one the entry body owns, such as `inbox[0]` or `b.value` of a local `b = Box(Event())`, whose buffer could be reused during the park after it was checked; and a place reached through a weak pointer or a borrowed parameter, whose target could be destroyed meanwhile.
- **Lock guards.** A lock guard that the call consumes, as a `Condvar` wait does, qualifies when the entry body made it by calling a **guard-making method** directly on a place that meets the path rule, or as the result of an earlier such wait on it. A guard-making method is declared by a type whose `unsafe Synchronized` conformance promises that its guards point only into its lock ([07](07-concurrency.md#the-synchronized-contract)), as `Mutex.lock()` and `RwLock.write()` are. Its guard points into the lock, which lies in that place or in `.system` state that a value stored there points to, so that place covers it. A guard that any other function returns, including a method that passes one on or a method of a derived `Synchronized` type, doesn't qualify, since its dependency set names that call's arguments, not where the lock lies.

Holding no section, a parked thread can't keep a reset arena's or an unregistered heap's memory from being released ([06](06-memory-and-allocators.md)), and only `.system` is never released, so:

- **the heap state a parking wait parks on comes from `.system`**, as the `@parks` promise requires ([below](#writing-a-parking-wait-the-parks-promise)), and std's queues, `Channel`s and `Future`s meet it;
- **an entry literal's out-of-line context always comes from `.system`**, whatever the current allocator is. Inline captures lie in the closure value, which a qualifying call keeps in a global or the entry body's own storage;
- **everything else** is on the thread's own stack, is in a global, which is never freed ([above](#at-exit-reclaim-then-close-entry)), or in the thread's own copy of a thread-local, which lasts until its teardown, is an owning value, whose first open in a new section, or after a checkpoint or an `await`, sees any reset or unregistration before it ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)), or is an object's value, which each access through its owner or a weak pointer checks ([03](03-handles-and-objects.md#destroying-an-object)). So a captured `List` from a level arena that was reset while the thread slept panics the next time it is opened, and a captured `Slice` into a blob from that arena reads `nil` ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)).

### Writing a parking wait: the `@parks` promise

**`@parks` is one of the unverified promises** ([11](11-errors-and-safety.md#safe-modules)). A `@parks` function promises:

- **where it parks**: only on a word inside its receiver or a borrowed or `mutable` argument, on a word inside the heap state one of them points to, which comes from `.system`, or on the calling thread's own park word, which the runtime owns, as `Thread.sleep` does;
- **how it parks**: through `unsafe Runtime.park(on word: *UInt32, expected: UInt32, timeout: Int?) -> Bool`, which parks the calling thread on `word` if it still holds `expected`, until another thread wakes it or `timeout` nanoseconds pass, and returns `false` only when the timeout passed. It may also return early, so its caller checks its condition again. Its caller promises that `word` stays live and is accessed only atomically meanwhile. `unsafe Runtime.wake(on word: *UInt32, count: Int)` wakes up to `count` threads parked on `word`;
- **what it touches**: while parked, only that word. It reads everything else after re-entering, and a lock guard it consumes holds no access across the park: it ends the guard's access before parking and takes it again through the lock after re-entering, as a `Condvar` wait does.

Any `unsafe` code may call `Runtime.park`. The call parks inside the section and just blocks, except at the top level ([above](#where-a-checkpoint-can-go)) of a `@parks` function whose own call is a checkpoint, where it leaves the section and re-enters it before returning. As for `@entry` ([above](#loops-owned-by-libraries-entry-functions)), a `task func` or an accessor, whose code runs after its call or its `yield`, is never `@parks`. The compiler treats each `Runtime.park` call at a `@parks` function's top level as a checkpoint: every open after it checks again, and no borrow or dynamic access is live across it, except the function's receiver and unscoped parameters, and a lock guard it consumes, whose access it ends across the park (above) and whose places the caller's check covers ([above](#what-a-wait-may-borrow)). A call to another `@parks` function there counts the same way when every place it borrows is the function's receiver or an unscoped parameter, a place reached from one of those through stored fields, inline array elements and enum payloads only, with no projection on the way, or a lock guard that a guard-making method made from one of those or that an earlier such call returned, so a queue built on a `Mutex` and a `Condvar` can declare a `@parks` wait of its own, whose `while g.value.isEmpty { g = self.cv.wait(consume g) }` loops.
