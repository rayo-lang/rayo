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

**`ThreadScope.run`, at the top of this chapter, returns only when every thread its block spawned has finished, its teardown included.** So its threads may borrow the caller's locals, as the spawned closure there borrows `world.bodies`. It is declared as:

```swift
static func run<R: ~Scoped>(_ body: consuming (mutable ThreadScope) -> R) -> R { … }   // ThreadScope's: runs the block once
```

The block takes the scope as a `mutable ThreadScope`, so a helper can take the scope as a parameter of that type. The block is called once, so it may write and move its captures, as `Mutex.lock`'s may ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)).

**`spawn` takes the closure by its concrete type and moves it into the scope** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)):

```swift
mutating func spawn(_ body: some consuming @sendable () -> Void) { … }   // ThreadScope's: the literal itself, not a view of it
```

A parameter of function type would get only a view of the literal, which dies at the end of its statement while the thread still runs it.

**The scope `s` absorbs what each spawned closure borrows and carries, with the same kinds, until the block returns.** This follows from rule 4, absorption ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)), since the scope's type is unsealed and scoped, as the library's promise requires ([below](#the-librarys-promise)). So nothing a spawned closure captures by reference can change or die before the block returns. A second `spawn` that writes `world.bodies`, or the block touching it after the first `spawn`, conflicts as two arguments of one call do:

```swift
ThreadScope.run { s in
    s.spawn { integrate(&world.bodies, dt: dt) }
    print(world.bodies.count)                               // error: 's' borrows 'world.bodies' exclusively until the block returns
}
```

**The scope joins every thread its block spawned, whether the block returns or a panic unwinds out of it.** An unwind out of the block stops at `ThreadScope.run` until every spawned thread has finished, and then goes on out of it. So no spawned thread outlives a borrow it was lent, however the block ends.

**A panic in a spawned thread stops at that thread, and `ThreadScope.run` resumes it once every thread has finished:**

```swift
ThreadScope.run { s in
    s.spawn { integrate(&world.bodies, dt: dt) }            // if this panics, its panic waits for the join
    mix(&world.audio)                                       // and this still runs
}                                                           // every thread has finished: a spawned thread's panic resumes here
```

The panic unwinds the spawned closure's frames on its own thread, and destroys the closure, while the block and the other spawned threads run on ([below](#panics-in-lent-work)). Once all of them have finished, `ThreadScope.run` resumes the panic on the calling thread with `resumePanic` ([10](../10-errors-and-safety/panics.md#resuming-a-panic-resumepanic)). So it unwinds the caller as a panic in the block would, and keeps the message and location it was reported with. Joining a `Thread` reports a panic the same way ([below](#joining-a-thread)).

**When several panics happen, in the block or its threads, the first one reported goes on** ([below](#panics-in-lent-work)).

**During startup, `spawn` runs its closure on the startup thread before it returns** ([below](#lent-work-during-startup)). So the scope's promise holds then too, with no thread to wait for.

### The library's promise

**Lending is the library's `unsafe` promise.** A scoped value, such as a closure that borrows the caller's locals, reaches another thread only through a library's `unsafe` code, which promises:

- **to move only `Sendable` values between threads.** The closures it takes are `@sendable`, and whatever it passes them is `Sendable`. Whatever it hands back from them to the lending thread is `Sendable` too: their results, the errors they fail with and the panics that end them included. Each value it hands over is made and written before the receiving thread's first use of it, in the memory model's happens-before order ([Atomics and locks](synchronization.md#atomics-and-locks));
- **to call the value only as its kind allows**, each call of a `mutating` one happening before the next;
- **to keep it past the call it was given to only in a type that is unsealed and scoped**, as the `ThreadScope` that `ThreadScope.run` lends its block keeps what `spawn` is given ([02](../02-views-and-dependencies/dependency-projection-and-results.md#shallow-values)). So the value that keeps it absorbs what it borrows for as long as it is kept. While that call runs, a raw pointer to it may pass through any storage that only the library's `unsafe` code reads, such as a global work queue;
- **to have every other thread done with it by the time the borrows it carries may end**, every access they made through it happening before then. That time is when the call that lent them returns or a panic unwinds out of it, as for the job system's `join`, or, for a value kept as above, the last use of the value that keeps it.

  So the type that keeps it is one of these:
    - one that safe code can make and drop, which declares a `deinit` that waits, making destroying it a use ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it));
    - one that only the library makes, such as the `ThreadScope` that `ThreadScope.run` lends its block, where the library waits before the call that lends it returns or unwinds;
- **never to hand it to a thread that is queued past that time**, as `Runtime.startThread` queues every thread it starts during startup. Such a thread starts only once startup ends, when the borrows the value carries may have ended. The `.queued` result of the start tells the library so ([below](#lent-work-and-queued-threads)).

**By the first promise, a closure that returns a lock guard taken on a worker, or an object made there, is rejected at the call**, since neither is `Sendable`.

**The borrowed memory stays valid while it is lent.** The lender can't free it while the borrow lasts. A reset or an unregistration of its allocator panics while an open, the lender's or a worker's, still lends from it ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).

**An unscoped `Sendable` value needs no such promise**, since it can't borrow.

### Panics in lent work

**A panic in lent work reaches the lending thread, as a panic in a closure the lender called itself would.** In std's job system, each piece of work runs under a recovery point of its own ([10](../10-errors-and-safety/panics.md#catching-a-panic-catchpanic)), on whichever thread runs it, the lender included. So a piece's panic unwinds only that piece's frames, and the thread goes on with other work. Once every piece has finished, the lending call resumes the panic on the lending thread with `resumePanic`, as `ThreadScope.run` does ([above](#scoped-threads)). The panic then unwinds out of the lending call, such as the job system's `join` or `forEachInParallel`.

**When several panics compete, the first one reported goes on**, and the lending call drops the others, which were reported already. That holds for `ThreadScope.run`, the job system's `join` and parallel loops, whether a panic happens in a piece or on the lending thread. The runtime reports panics in one order, which puts a root cause, such as the panic that poisoned a lock, before the panics that follow from it ([10](../10-errors-and-safety/panics.md#what-a-panic-does)).

**The job system's `join` runs both closures even when one panics**, since both are lent already. Once a piece has panicked, a parallel loop may skip the elements no piece has started, since the call unwinds anyway. So the code after a caught panic can't rely on which elements the loop's body saw.

**A panic wakes no parked thread.** So when a piece waits for something that only the code that panicked would have done, the piece waits for ever, and so does the lending call, or a `join()`. Code that other threads wait on signals them in a `defer`, which runs on every way out, the unwind included:

```swift
let ready = Event()
ThreadScope.run { s in
    s.spawn { ready.wait(); process(&output) }     // parks until 'ready' is signalled
    defer { ready.signal() }                       // runs when the block unwinds too
    prepare(&input)                                // may panic: without the defer, the spawned thread would wait for ever
}
```

During startup, this example panics at the spawned closure's `wait()` instead, since lent work then runs inline ([below](#lent-work-during-startup)).

**A job system of one's own carries a panic back the same way**, with `catchPanic` around each piece and `resumePanic` on the lending thread ([10](../10-errors-and-safety/panics.md#resuming-a-panic-resumepanic)). Of several panics, it resumes the one with the lowest `sequence`, which is the first reported ([10](../10-errors-and-safety/panics.md#the-panic-value)). It still waits for every piece whether the lending call returns or unwinds, as the library's promise requires ([above](#the-librarys-promise)).

### Lent work during startup

**During startup, std's lending calls run their work inline, on the startup thread, before they return.** That covers `ThreadScope.spawn`, the job system's `join` and parallel loops. Startup is single-threaded, so `Runtime.startThread` only queues a thread then, and a queued thread starts once startup ends ([Initialization at startup](global-state.md#initialization-at-startup)). By then the lending call has returned or unwound, and the borrows it lent may have ended. Running the work inline keeps every borrow in the frame that lent it, as the library's promise requires ([above](#the-librarys-promise)):

```swift
let table = catchPanic {                          // a global's initializer, run during startup
    var buf = List<Int>()
    ThreadScope.run { s in
        s.spawn { buf.append(1) }                 // runs here, before 'spawn' returns
    }
    return buf
} recover: { _ in List<Int>() }
```

**Inline work runs as code the block calls, so it follows the rules for startup code:**

- **Order.** Each closure runs at its `spawn` call, in `spawn` order, before the rest of the block.
- **Parking.** A closure that parks panics, as any wait that would park during startup does ([Initialization at startup](global-state.md#initialization-at-startup)). So the `Event` example above panics during startup, at the spawned closure's `wait()`.
- **Locks.** A closure that locks a mutex the block holds panics, as relocking a held `Mutex` does ([Locks](synchronization.md#locks-mutex-and-rwlock)).
- **Spinning.** A closure that spins on an atomic until the block sets it hangs for ever, since the block runs only after the closure returns.
- **Panics.** An inline closure's panic stops at the closure and waits for the end of `ThreadScope.run`, as outside startup ([above](#scoped-threads)). So the block keeps running after it.

### Thread-locals in lent work

**Thread-locals belong to the thread that runs the code.** Lent work that reads a `@threadlocal var`, or allocates through the current allocator, gets the running thread's copy. Work that the lending thread runs itself, as the job system's `join` may, touches the lender's copy. A conflict with an access the waiting lender holds then panics on the ordinary access mark ([Thread-locals](global-state.md#thread-locals)).

## Work that outlives the caller: threads

```swift
func startRenderer() -> (Thread<Void>, Sender<Shared<Snapshot>>) {           // called from main, after startup
    let (tx, rx) = Channel<Shared<Snapshot>>.make(capacity: 3)
    let render: Thread<Void> = Thread.start(name: "render") { [move rx] in   // the thread owns the receiver
        while true { draw(rx.waitPop()) }                                    // parks until the simulation sends one
    }
    return (render, tx)                                                      // the simulation keeps the sender
}

let snapshots = SpscQueue<Shared<Snapshot>>(capacity: 3)                     // instead of a channel, a global queue: a Synchronized let

func startRendererOnGlobal() -> Thread<Void> {
    Thread.start(name: "render") {
        while true { draw(snapshots.waitPop()) }                             // parks until the simulation pushes one
    }
}
```

**`Thread.start` starts a thread that may outlive the function that started it**, as the render thread outlives `startRenderer`. It runs its body once on the new thread, and returns a `Thread<R>`, where `R` is the body's result type ([below](#joining-a-thread)):

```swift
struct Thread<R: Sendable & ~Scoped>(…): ~Copyable    // R: the body's result type
static func start(name: StaticString = "", _ body: owned Closure<consuming @sendable () -> R>) -> Thread<R> { … }
                                                      // Thread<R>'s: the body, handed over; a call infers R from it
```

**A `Thread<R>` is move-only and `Sendable`.** It is move-only since it is the one value that can join its thread. It is `Sendable`, since `R` always is, so any thread may join it.

**`Thread.start` panics when `Runtime.startThread` refuses the start**, since it has no thread to return. That happens when the platform can't start a thread, or after shutdown ([below](#starting-a-thread-runtimestartthread)). The unwind destroys the body and its captures. During startup the runtime queues the thread instead, and `Thread.start` returns its `Thread` at once.

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

The thread has ended once its body has returned, or a panic has ended it, and its teardown has run ([Thread teardown](global-state.md#thread-teardown)). `Thread.start` waits for that through the runtime's `ended` signal ([below](#starting-a-thread-runtimestartthread)). So everything the thread did, its teardown's `deinit`s included, happens before `join()` returns. A thread is joined at most once, since `join()` consumes the `Thread`.

**A thread that joins its own `Thread` panics**, as relocking a `Mutex` it holds does, since it would wait for itself for ever. It can hold its own `Thread` only if one was sent to it, such as through a channel.

**The result crosses from the thread to the joiner, so `R` is `Sendable` and unscoped**, as what lent work hands back is ([above](#the-librarys-promise)). The thread keeps the result in the state it shares with its `Thread` until `join()` moves it out. A body that can fail returns a `Result`, so its error reaches the joiner as a value, as `checksum`'s does. A thread whose body returns nothing is a `Thread<Void>`, and `join()` on it returns `Void`.

**The unused-value rule applies to `join()`'s result as to any call's** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values)). So a joiner that waits for a `Thread<R>` but has no use for its result drops the result on purpose. Each of these lines stands in place of the `join()` above, since a thread is joined once:

```swift
checksum.join()                   // error: the UInt32!IoError is never used
_ = checksum.join()               // fine: waits for the thread, and drops its result
```

**A panic in a thread's body ends the thread, and `join()` resumes it in the joiner.** The panic was reported when it happened, and unwinds the body's frames, destroying what the body owns, its captures included ([10](../10-errors-and-safety/panics.md#what-a-panic-does)). Then the thread's teardown runs as when the body returns. `Thread.start` runs the body under a recovery point of its own, which keeps the panic for `join()`. `join()` resumes it on the joining thread with `resumePanic`, as `ThreadScope.run` resumes a spawned thread's panic ([above](#scoped-threads)). A joiner that handles the panic itself wraps the call in `catchPanic` ([10](../10-errors-and-safety/panics.md#catching-a-panic-catchpanic)), again in place of the first `join()`:

```swift
let sum: UInt32? = catchPanic {
    try? checksum.join()                                  // nil if the body failed with an error
} recover: { p in
    log("checksum thread panicked: \(p.message)")
    return nil                                            // and nil if it panicked
}
```

**A panic in another thread can leave `join()` waiting for ever**, when the joined thread waits for something that only the panicking code would have done ([above](#panics-in-lent-work)).

**Dropping a `Thread` detaches the thread.** A **detached thread** runs on to the end of its body and tears down by itself, and nothing can join it any more. Its panic, if it has one, is reported when it happens, and no code sees it. A detached thread that is still running when `main` returns ends where it stands, as every thread other than the main one does ([Shutdown](global-state.md#shutdown)).

**Detaching leaks nothing.** The thread owns what its body captured, and the state it shares with its `Thread` is freed by whichever of the two lets go last. No `join()` will take the body's result, so it is destroyed as soon as nothing can take it:

- **when the body returns**, on the thread, before its teardown, if the `Thread` was dropped first;
- **at the drop**, on the dropping thread, if the body had returned already. `R` is `Sendable`, so that thread may destroy it.

So no Rayo code of the thread runs after its teardown.

**The unused-value rule makes every detach visible.** `Thread.start` returns the `Thread`, so code that never joins it drops it on purpose with `_ =`, as the examples above do ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values)).

### Starting a thread: `Runtime.startThread`

**`Runtime.startThread` is the runtime's one primitive for starting a thread:**

```swift
static func startThread(_ body: owned Closure<consuming @sendable () -> Void>,   // Runtime's: the body, handed over
                        ended: owned Shared<Event>?) -> ThreadStart { … }          // 'ended': signalled after the thread's teardown

enum ThreadStart {
    case started                                             // a new thread runs the body
    case queued                                              // during startup: the thread starts once startup ends
    case refused(Closure<consuming @sendable () -> Void>)    // the body, unstarted
}
```

**The result says what became of the body:**

- **`.started`** once a new platform thread runs it, with no Rayo frame below it. The call happens before the body begins.
- **`.queued`** during startup, when the thread waits for startup to end ([below](#lent-work-and-queued-threads)).
- **`.refused`**, holding the body unstarted, when the platform can't start a thread, or after shutdown ([Shutdown](global-state.md#shutdown)). The runtime then drops `ended` unsignalled.

**The runtime signals `ended`, when it is given one, once the thread's teardown has run** ([Thread teardown](global-state.md#thread-teardown)). Signalling it is the thread's last act in Rayo, so everything the thread did, its teardown's `deinit`s included, happens before a wait on `ended` returns. That is how `join()` and `ThreadScope.run` wait for a thread's teardown ([above](#joining-a-thread)). The runtime then releases its owner of `ended`, which runs no Rayo code even when it is the last owner, since destroying an `Event` runs no `deinit` ([Snapshots, one-time values and waits](synchronization.md#snapshots-one-time-values-and-waits)).

**A panic that unwinds out of `body` ends the thread as an uncaught panic does** ([10](../10-errors-and-safety/panics.md#uncaught-panics)). The runtime carries the panic nowhere but the report. So `Thread.start` and job systems run their work under `catchPanic` inside the body, to carry a panic back to a joiner or lender ([above](#panics-in-lent-work)).

### Lent work and queued threads

**During startup, `Runtime.startThread` returns `.queued` at once, and the thread waits until startup ends** ([Initialization at startup](global-state.md#initialization-at-startup)), since startup is single-threaded. A queued thread that the platform can't start then panics.

**std guarantees that no lent work is ever queued**, since its lending calls run their work inline during startup ([above](#lent-work-during-startup)). Another library keeps the same guarantee through the result: it starts a worker before it hands the worker any lent work, and when the start comes back `.queued`, it runs the work inline instead.

**A library may also start threads through the platform's API with `import c`.** The start routine is then a C entry ([08](../08-c-interop/calling-rayo-from-c.md#c-entries-and-threads)). The runtime doesn't know that thread until it enters, so entering before startup ends or after shutdown panics, as for any C thread.
