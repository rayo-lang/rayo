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
- **What a call begins ends with it**, since rule 5 lets no function return, throw or store a view of what it owns or began ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-5-the-callee-side)). A lock guard is released on the thread that took it ([Locks: `Mutex` and `RwLock`](synchronization.md#locks-mutex-and-rwlock)). So nothing a closure began on one thread is left for another.

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

**The scope `s` absorbs what each spawned closure borrows and carries, with the same kinds, until the block returns.** This follows from rule 4, absorption ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-4-absorption)), since the scope's type is unsealed and scoped, as the library's promise requires ([below](#the-librarys-promise)). So nothing a spawned closure captures by reference can change or die before the block returns. A second `spawn` that writes `world.bodies`, or the block touching it after the first `spawn`, conflicts as two arguments of one call do:

```swift
Thread.scope { s in
    s.spawn { integrate(&world.bodies, dt: dt) }
    print(world.bodies.count)                               // error: 's' borrows 'world.bodies' exclusively until the block returns
}
```

### The library's promise

**Lending is the library's `unsafe` promise.** A scoped value, such as a closure that borrows the caller's locals, reaches another thread only through a library's `unsafe` code, which promises:

- **to move only `Sendable` values between threads.** The closures it takes are `@sendable`, and whatever it passes them is `Sendable`. Whatever it hands back from them to the lending thread is `Sendable` too: their results and the errors they throw. Each value it hands over is made and written before the receiving thread's first use of it, in the memory model's happens-before order ([Atomics and locks](synchronization.md#atomics-and-locks));
- **to call the value only as its kind allows**, each call of a `mutating` one happening before the next;
- **to keep it past the call it was given to only in a type that is unsealed and scoped**, as `Thread.scope`'s scope keeps what `spawn` is given ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#shallow-values)). So the value that keeps it absorbs what it borrows for as long as it is kept. While that call runs, a raw pointer to it may pass through any storage that only the library's `unsafe` code reads, such as a global work queue;
- **to have every other thread done with it by the time the borrows it carries may end**, every access they made through it happening before then. That time is when the call that lent them returns, as for `join`, or, for a value kept as above, the last use of the value that keeps it.

  So the type that keeps it is one of these:
    - one that safe code can make and drop, which declares a `deinit` that waits, making destroying it a use ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it));
    - one that only the library makes, like `Thread.scope`'s scope, where the library waits before the call that lends it returns.

**By the first promise, a closure that returns or throws a lock guard taken on a worker, or an object made there, is rejected at the call**, since neither is `Sendable`.

**The borrowed memory stays valid while it is lent.** The lender can't free it while the borrow lasts. A reset or an unregistration of its allocator panics while an open, the lender's or a worker's, still lends from it ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).

**An unscoped `Sendable` value needs no such promise**, since it can't borrow.

### Thread-locals in lent work

**Thread-locals belong to the thread that runs the code.** Lent work that reads a `@threadlocal var`, or allocates through the current allocator, gets the running thread's copy. Work that the lending thread runs itself, as a join may, touches the lender's copy. A conflict with an access the waiting lender holds then panics on the ordinary access mark ([Thread-locals](global-state.md#thread-locals)).

## Work that outlives the caller: threads

```swift
func startRenderer() -> (Thread, Sender<Shared<Snapshot>>) {                 // called from main, after startup
    let (tx, rx) = Channel<Shared<Snapshot>>.make(capacity: 3)
    let render = Thread.loop(name: "render", receiving: rx) { snap in          // 'rx' moves in; one iteration per snapshot
        draw(snap)
    }
    return (render, tx)                                                       // the simulation keeps the sender
}

let snapshots = SpscQueue<Shared<Snapshot>>(capacity: 3)                     // instead of a channel, a global queue: a Synchronized let

func startRendererOnGlobal() -> Thread {
    Thread.start(name: "render") {
        while true { draw(snapshots.waitPop()) }                              // parks until the simulation pushes one
    }
}
```

**`Thread.loop` and `Thread.start` start a thread that may outlive the function that started it**, as the render thread outlives `startRenderer`:

- **`Thread.loop`** runs its body once per item, on a thread that owns the `Receiver`, and parks between items.
- **`Thread.start`** runs its closure once.

### What a thread can share

**A closure that another thread may run after the call it was passed to returns is unscoped and `Sendable`**, such as a `@sendable` `Closure`. It is unscoped since it outlives that call, and `Sendable` since another thread runs it. A thread's body is one such closure. Being unscoped, it can't capture borrows. It owns its captures, which must be `Sendable`, and lists them ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)):

```swift
var level = loadLevel()                                      // move-only: owns its lists
let bounces = 3
Thread.start(name: "bake") {
    bakeLighting(level, bounces: bounces)                    // error: unlisted captures; a thread body can't borrow them
}
Thread.start(name: "bake") { [move level, copy bounces] in   // fine: the closure owns 'level', and a copy of 'bounces'
    bakeLighting(level, bounces: bounces)
}
```

### Starting a thread: `Runtime.startThread`

**`Runtime.startThread` is the runtime's one primitive for starting a thread:**

```swift
static func startThread(_ body: owned Closure<consuming @sendable () -> Void>)   // Runtime's: the body, handed over
    -> Closure<consuming @sendable () -> Void>? { … }                            // nil once the thread has started
```

The new platform thread runs `body` with no Rayo frame below it. The call returns `nil` once the thread has started. It returns `body`, unstarted, when the platform can't start a thread, or after shutdown ([Shutdown](global-state.md#shutdown)). The call happens before the body begins.

**During startup it returns `nil` at once, and queues the thread until startup ends** ([Initialization at startup](global-state.md#initialization-at-startup)), since startup is single-threaded. A queued thread that the platform can't start then panics.

**A library may also start threads through the platform's API with `import c`.** The start routine is then a C entry ([08](../08-c-interop/calling-rayo-from-c.md#c-entries-and-threads)). The runtime doesn't know that thread until it enters, so entering before startup ends or after shutdown panics, as for any C thread.
