# Lending work and starting threads

[07 · Concurrency](../07-concurrency.md)

## Lending work to other threads

A job system is a Rayo library whose safe API takes function values that borrow the caller's data, and runs them on its threads as **lent work**. The library finishes the work before those borrows can end ([below](#the-librarys-promise)):

```swift
particles.forEachInParallel { p in                          // @sendable (mutable Particle) -> Void: not mutating, so any thread
    p.vel += gravity * dt
    p.pos += p.vel * dt
}
```

**These rules make what its users write race-free:**

- **Only `Sendable` values reach its threads** ([below](#the-librarys-promise)). A closure that captures an object's owner or weak pointer, even by reference, doesn't compile.
- **Closure kinds say how a function value may be called** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)):
    - a non-`mutating` one by any number of threads at once, since it only reads its captures;
    - a `mutating` one by one thread at a time, each call happening before the next, since calling it changes the closure itself;
    - a `consuming` one once, since the call consumes it.
- **Exclusivity holds across a call's arguments**, closures included, since a closure literal borrows what it captures for as long as the call has it. So the second `join` at the top of this chapter is rejected, as `f(&x, x)` is.
- **What a call begins ends with it**, since rule 5 lets no function return or store a view of what it owns or began ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)). A lock guard is released on the thread that took it ([Locks: `Mutex` and `RwLock`](synchronization.md#locks-mutex-and-rwlock)). So nothing a closure began on one thread is left for another.

**Writing a shared place from a parallel loop's body is a type error:**

```swift
particles.forEachInParallel { p in
    grid[cell(p.pos)] += p.mass     // error: writes 'grid', so the closure is 'mutating', but the loop runs it on many threads at once
}
```

**With `grid` an `AtomicArray<Float>`, the body compiles**, since each write is an atomic add through a shared borrow ([Atomics and locks](synchronization.md#atomics-and-locks)):

```swift
particles.forEachInParallel { p in
    grid.add(cell(p.pos), p.mass, .relaxed)     // fine: an atomic add through a shared borrow of 'grid'
}
```

### Scoped threads

**`Thread.scope`, at the top of this chapter, returns only when every thread its block spawned has finished.** So its threads may borrow the caller's locals, as the spawned closure there borrows `world.bodies`. It is declared as:

```swift
static func scope<R: ~Scoped>(_ body: consuming (mutable ThreadScope) -> R) -> R { … }   // Thread's: runs the block once
```

The block takes the scope as a `mutable ThreadScope`, so a helper can take the scope as a parameter of that type. The block is called once, so it may write and move its captures, as `Mutex.lock`'s may ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)).

**`spawn` takes the closure by its concrete type and moves it into the scope** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)):

```swift
mutating func spawn(_ body: some consuming @sendable () -> Void) { … }   // ThreadScope's: the literal itself, not a view of it
```

A parameter of function type would get only a view of the literal, which dies at the end of its statement while the thread still runs it.

**The scope `s` absorbs what each spawned closure borrows and carries, with the same kinds, until the block returns.** This follows from rule 4, absorption ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)), since the scope's type is unsealed and scoped, as the library's promise requires ([below](#the-librarys-promise)). So nothing a spawned closure captures by reference can change or die before the block returns. A second `spawn` that writes `world.bodies`, or the block touching it after the first `spawn`, conflicts as two arguments of one call do:

```swift
Thread.scope { s in
    s.spawn { integrate(&world.bodies, dt: dt) }
    print(world.bodies.count)                               // error: 's' borrows 'world.bodies' exclusively until the block returns
}
```

**The scope joins every thread its block spawned, whether the block returns or a panic unwinds out of it.** An unwind out of the block stops at `Thread.scope` until every spawned thread has finished, and then goes on out of it. So no spawned thread outlives a borrow it was lent, however the block ends.

**A panic in a spawned thread stops at that thread, and `Thread.scope` resumes it once every thread has finished:**

```swift
Thread.scope { s in
    s.spawn { integrate(&world.bodies, dt: dt) }            // if this panics, its panic waits for the join
    mix(&world.audio)                                       // and this still runs
}                                                           // every thread has finished: a spawned thread's panic resumes here
```

The panic unwinds the spawned closure's frames on its own thread, and destroys the closure, while the block and the other spawned threads run on ([Panics in lent work](#panics-in-lent-work)). Once all of them have finished, `Thread.scope` resumes the panic on the calling thread with `resumePanic` ([10](../10-errors-and-safety/panics.md#resuming-a-panic-resumepanic)). So it unwinds the caller as a panic in the block would, and keeps the message and location it was reported with. Joining a `Thread` reports a panic the same way ([below](#joining-a-thread)).

**One panic goes on out of `Thread.scope` when several happen.** Each was reported when it happened, so the scope drops the others. The one that goes on is:

- the block's own, when a panic unwinds out of the block;
- otherwise, the panic of the first thread spawned among those that panicked.

### The library's promise

**Lending is the library's `unsafe` promise.** A scoped value, such as a closure that borrows the caller's locals, reaches another thread only through a library's `unsafe` code, which promises:

- **to move only `Sendable` values between threads.** The closures it takes are `@sendable`, and whatever it passes them is `Sendable`. Whatever it hands back from them to the lending thread is `Sendable` too: their results, the errors they fail with and the panics that end them included. Each value it hands over is made and written before the receiving thread's first use of it, in the memory model's happens-before order ([Atomics and locks](synchronization.md#atomics-and-locks));
- **to call the value only as its kind allows**, each call of a `mutating` one happening before the next;
- **to keep it past the call it was given to only in a type that is unsealed and scoped**, as `Thread.scope`'s scope keeps what `spawn` is given ([02](../02-views-and-dependencies/dependency-projection-and-results.md#shallow-values)). So the value that keeps it absorbs what it borrows for as long as it is kept. While that call runs, a raw pointer to it may pass through any storage that only the library's `unsafe` code reads, such as a global work queue;
- **to have every other thread done with it by the time the borrows it carries may end**, every access they made through it happening before then. That time is when the call that lent them returns or a panic unwinds out of it, as for `join`, or, for a value kept as above, the last use of the value that keeps it.

  So the type that keeps it is one of these:
    - one that safe code can make and drop, which declares a `deinit` that waits, making destroying it a use ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it));
    - one that only the library makes, like `Thread.scope`'s scope, where the library waits before the call that lends it returns or unwinds.

**By the first promise, a closure that returns a lock guard taken on a worker, or an object made there, is rejected at the call**, since neither is `Sendable`.

**The borrowed memory stays valid while it is lent.** The lender can't free it while the borrow lasts. A reset or an unregistration of its allocator panics while an open, the lender's or a worker's, still lends from it ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).

**An unscoped `Sendable` value needs no such promise**, since it can't borrow.

### Panics in lent work

**A panic in lent work reaches the lending thread, as a panic in a closure the lender called itself would.** In std's job system, each piece of work runs under a recovery point of its own ([10](../10-errors-and-safety/panics.md#catching-a-panic-catchpanic)), on whichever thread runs it, the lender included. So a piece's panic unwinds only that piece's frames, and the thread goes on with other work. Once every piece has finished, the lending call resumes the panic on the lending thread with `resumePanic`, as `Thread.scope` does ([above](#scoped-threads)). The panic then unwinds out of the lending call, such as `join` or `forEachInParallel`.

**One panic goes on out of the lending call when several pieces panic**, the first in the call's own order: `join`'s first closure before its second, and in a parallel loop, the piece holding the earliest element. Each panic was reported when it happened, so the call drops the others.

**Once a piece has panicked, a parallel loop may skip the elements no piece has started**, since the call unwinds anyway. So the code after a caught panic can't rely on which elements the loop's body saw.

**A job system of one's own carries a panic back the same way**, with `catchPanic` around each piece and `resumePanic` on the lending thread ([10](../10-errors-and-safety/panics.md#resuming-a-panic-resumepanic)). It still waits for every piece whether the lending call returns or unwinds, as the library's promise requires ([above](#the-librarys-promise)).

### Thread-locals in lent work

**Thread-locals belong to the thread that runs the code.** Lent work that reads a `@threadlocal var`, or allocates through the current allocator, gets the running thread's copy. Work that the lending thread runs itself, as a join may, touches the lender's copy. A conflict with an access the waiting lender holds then panics on the ordinary access mark ([Thread-locals](global-state.md#thread-locals)).

## Work that outlives the caller: threads

```swift
func startRenderer() -> (Thread<Void>, Sender<Shared<Snapshot>>) {           // called from main, after startup
    let (tx, rx) = Channel<Shared<Snapshot>>.make(capacity: 3)
    let render = Thread.start(name: "render") { [move rx] in                   // the thread owns the receiver
        while true { draw(rx.waitPop()) }                                       // parks until the simulation sends one
    }
    return (render, tx)                                                       // the simulation keeps the sender
}

let snapshots = SpscQueue<Shared<Snapshot>>(capacity: 3)                     // instead of a channel, a global queue: a Synchronized let

func startRendererOnGlobal() -> Thread<Void> {
    Thread.start(name: "render") {
        while true { draw(snapshots.waitPop()) }                              // parks until the simulation pushes one
    }
}
```

**`Thread.start` starts a thread that may outlive the function that started it**, as the render thread outlives `startRenderer`. It runs its body once on the new thread, and returns a `Thread<R>`, where `R` is the body's result type ([Joining a thread](#joining-a-thread)):

```swift
struct Thread<R: Sendable & ~Scoped>(…)               // R: the body's result type
static func start(name: StaticString = "", _ body: owned Closure<consuming @sendable () -> R>) -> Thread<R> { … }
                                                      // Thread<R>'s: the body, handed over; a call infers R from it
```

**A thread that serves a stream of items owns the receiving end, and waits on it in a loop**, as the render thread does with `rx`. Between items, `waitPop()` parks it ([Queues and channels](synchronization.md#queues-and-channels)).

### What a thread can share

**A closure that another thread may run after the call it was passed to returns is unscoped and `Sendable`**, such as a `@sendable` `Closure`. It is unscoped since it outlives that call, and `Sendable` since another thread runs it. A thread's body is one such closure. Being unscoped, it can't capture borrows. It owns its captures, which must be `Sendable`, and lists them ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)):

```swift
var level = loadLevel()                                      // move-only: owns its lists
let bounces = 3
_ = Thread.start(name: "bake") {
    bakeLighting(level, bounces: bounces)                        // error: unlisted captures; a thread body can't borrow them
}
_ = Thread.start(name: "bake") { [move level, copy bounces] in   // fine: owns 'level' and a copy of 'bounces'; '_ =' detaches it
    bakeLighting(level, bounces: bounces)
}
```

### Joining a thread

```swift
let checksum = Thread.start(name: "checksum") { [move path] in   // a Thread<UInt32!IoError>
    let bytes = try readFile(path.view)
    return crc32(bytes)
}
indexFolder(dir)                                                // runs on this thread meanwhile
let sum = try checksum.join()                                   // waits for the thread, then takes its result or propagates its error
```

**`join()` waits until the thread has ended, consumes its `Thread`, and returns what the body returned:**

```swift
consuming func join() -> R        // Thread<R>'s: returns once the thread has ended
```

The thread has ended once its body has returned, or a panic has ended it, and its teardown has run ([Thread teardown](global-state.md#thread-teardown)). So everything the thread did, its teardown's `deinit`s included, happens before `join()` returns. A thread is joined at most once, since `join()` consumes the `Thread`.

**The result crosses from the thread to the joiner, so `R` is `Sendable` and unscoped**, as what lent work hands back is ([above](#the-librarys-promise)). The thread keeps the result in the state it shares with its `Thread` until `join()` moves it out. A body that can fail returns a `Result`, so its error reaches the joiner as a value, as `checksum`'s does. A thread whose body returns nothing is a `Thread<Void>`, and `join()` on it returns `Void`.

**The unused-value rule applies to `join()`'s result as to any call's** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values)). So a joiner that waits for a `Thread<R>` but has no use for its result drops the result on purpose:

```swift
checksum.join()                   // error: the UInt32!IoError is never used
_ = checksum.join()               // fine: waits for the thread, and drops its result
```

**A panic in a thread's body ends the thread, and `join()` resumes it in the joiner.** The panic was reported when it happened, and unwinds the body's frames, destroying what the body owns, its captures included ([10](../10-errors-and-safety/panics.md#what-a-panic-does)). Then the thread's teardown runs as when the body returns. `Thread.start` runs the body under a recovery point of its own, which keeps the panic for `join()`. `join()` resumes it on the joining thread with `resumePanic`, as `Thread.scope` resumes a spawned thread's panic ([above](#scoped-threads)). A joiner that handles the panic itself wraps the call in `catchPanic` ([10](../10-errors-and-safety/panics.md#catching-a-panic-catchpanic)):

```swift
let sum: UInt32? = catchPanic {
    try? checksum.join()                                  // nil if the body failed with an error
} recover: { p in
    log("checksum thread panicked: \(p.message)")
    return nil                                            // and nil if it panicked
}
```

**Dropping a `Thread` detaches the thread.** A **detached thread** runs on to the end of its body and tears down by itself, and nothing can join it any more. Its panic, if it has one, is reported when it happens, and no code sees it. A detached thread that is still running when `main` returns ends where it stands, as every thread other than the main one does ([Shutdown](global-state.md#shutdown)).

**Detaching leaks nothing.** The thread owns what its body captured, and the state it shares with its `Thread` is freed by whichever of the two lets go last. The body's result, kept in that state, is destroyed with it, since no `join()` will take it: when the thread ends, or at the drop if the thread had already ended. `R` is `Sendable`, so either thread may destroy it.

**The unused-value rule makes every detach visible.** `Thread.start` returns the `Thread`, so code that never joins it drops it on purpose, with `_ = Thread.start { … }` ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values)).

### Starting a thread: `Runtime.startThread`

**`Runtime.startThread` is the runtime's one primitive for starting a thread:**

```swift
static func startThread(_ body: owned Closure<consuming @sendable () -> Void>)   // Runtime's: the body, handed over
    -> Closure<consuming @sendable () -> Void>? { … }                            // nil once the thread has started
```

The new platform thread runs `body` with no Rayo frame below it. The call returns `nil` once the thread has started. It returns `body`, unstarted, when the platform can't start a thread, or after shutdown ([Shutdown](global-state.md#shutdown)). The call happens before the body begins.

**A panic that unwinds out of `body` ends the thread as an uncaught panic does** ([10](../10-errors-and-safety/panics.md#uncaught-panics)). Only the report shows it, since no code waits on the thread through the runtime. So `Thread.start` and job systems run their work under `catchPanic` inside the body, to carry a panic back to a joiner or lender ([above](#panics-in-lent-work)).

**During startup it returns `nil` at once, and queues the thread until startup ends** ([Initialization at startup](global-state.md#initialization-at-startup)), since startup is single-threaded. A queued thread that the platform can't start then panics.

**A library may also start threads through the platform's API with `import c`.** The start routine is then a C entry ([08](../08-c-interop/calling-rayo-from-c.md#c-entries-and-threads)). The runtime doesn't know that thread until it enters, so entering before startup ends or after shutdown panics, as for any C thread.
