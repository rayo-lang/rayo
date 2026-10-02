# 07 · Concurrency

```swift
import std.jobs

join({ updateAI(&world.ai, sense: world.perception) },    // may run both closures at once, and returns when both are done
     { integrate(&world.bodies, dt: dt) })                 // fine: each closure writes a different field

join({ steer(&world.ai, around: world.bodies) },
     { integrate(&world.bodies, dt: dt) })                 // error: one closure reads 'world.bodies' while the other writes it

Thread.scope { s in                                        // threads that may borrow this function's locals
    s.spawn { integrate(&world.bodies, dt: dt) }           // runs on another thread
    mix(&world.audio)                                      // runs on this thread meanwhile
}                                                          // the spawned thread has finished here
```

**Threads, locks and job systems are libraries.** The language gives them the checking rules below, and the marker protocol `Sendable` for what may cross threads. The runtime starts, parks and wakes threads ([below](#starting-a-thread-runtimestartthread), [below](#parking-and-waking-a-thread)). The language's own construct is the `task` function, a coroutine that its owner resumes one step at a time ([below](#task-functions-explicitly-stepped-coroutines)).

## Why safe code can't race

**Only `Sendable` values reach another thread** ([next](#what-may-cross-threads-sendable)). Everything else stays on its own thread, where exclusivity and the dynamic tier check all its aliases. Safe code on two threads can reach the same memory only through:

1. **borrows**, which a library lends to another thread only for the length of a call, where exclusivity governs them statically ([below](#lending-work-to-other-threads));
2. **`Synchronized` types and channel ends**, which synchronize themselves ([below](#atomics-and-locks), [below](#queues-and-channels));
3. **`Shared<T>`**, whose value is `Frozen`, so never written, or `Synchronized`, so written only through its own synchronization ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners));
4. **`const`s, global `let`s and immortal data**, which every thread reads through shared borrows ([below](#global-state)). Immortal data, such as what a `StaticSpan` or `StaticString` views, is never written once a value names it ([09](09-compile-time.md#staticspan-views-of-immortal-data)).

Every other global that safe code can use is thread-local ([below](#global-state)). Reading a value from many threads at once needs nothing special, as a parallel loop shows:

```swift
let palette = buildPalette()                  // a local, read below by every thread at once
particles.forEachInParallel { p in            // may run on many threads at once
    p.color = palette.color(for: p.kind)      // fine: nothing writes 'palette'
}
```

## What may cross threads: `Sendable`

```swift
import c "audio.h"                                       // declarations land in module 'audio'

struct Enemy(var pos: Vec3, var hp: Float)               // Sendable: every field is
struct Hud(var root: WeakPointer<Widget>)                // not Sendable: holds a thread-bound weak pointer
struct GLTexture(let id: UInt32): ~Sendable              // opts out: must stay on the GL thread
struct AudioDevice(unsafe let device: *audio.AudioDev): unsafe Sendable   // a promise: the C audio API is thread-safe

Thread.start { [move enemies] in simulate(enemies) }     // fine: List<Enemy> is Sendable
Thread.start { [move hud] in draw(hud) }                 // error: 'Hud' isn't Sendable
```

**A value of a `Sendable` type may be used from another thread**: moved there, or borrowed there until the lending call returns. The compiler derives this marker protocol, as it derives `Copyable`:

- **A struct, enum, tuple, union or array** is `Sendable` when every stored field, payload and element is. For a generic type, the fields are checked with its type arguments substituted, so `Pair<Enemy>` of two `Enemy` fields is, and no `Tagged<T>` that also holds a `WeakPointer<Widget>` is, whatever `T` is.
- **A closure** is `Sendable` when every capture's type is, whether captured by reference or owned. A value of a `@sendable` function type, or a `Closure` of one, is `Sendable` ([05](05-protocols-generics-and-closures.md#function-typed-values)). A C function pointer is `Sendable` too.
- **`any P` and `mutable any P`** are `Sendable` only when `P` refines `Sendable`, or when they are written with `& Sendable`, which accepts only `Sendable` types ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).
- **Raw pointers**, and anything that holds one, aren't `Sendable`, unless its type declares `unsafe Sendable` or `unsafe Synchronized` ([below](#the-synchronized-contract)). **`UniquePointer` and `WeakPointer`** ([03](03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)), **lock guards** ([02](02-views-and-dependencies.md#lock-guards-are-released-on-the-thread-that-took-them)), and anything that holds one of them never are: their marks and locks belong to one thread. So declaring `unsafe Sendable` or `unsafe Synchronized` on such a type breaks its promise ([10](10-errors-and-safety.md#unverified-promises)).
- **std's owning containers** (`List`, `String`, `Map`, `Set`, `TrailingArray`, `Pool`, `StablePool`, `Box` and `Blob`), **the builtin `SoA`, and the views** `Span`, `MutableSpan`, `StringView`, `StaticSpan`, `StaticString`, `Borrow` and `MutableRef` each hold a raw pointer, so none derives `Sendable`. Each declares `unsafe Sendable` when every type it holds is `Sendable`: a `TrailingArray`'s header and elements, a `Map`'s keys and values, and each other container's or view's elements. The pointer in each names memory the value owns alone, immortal literal bytes, or memory it views under the borrow rules, so moving or lending the value moves or lends exactly what it holds. So `List<Enemy>` is `Sendable`, and `List<WeakPointer<Enemy>>` isn't.
- **`Shared<T>`, `WeakShared<T>`, `Sender<T>`, `Receiver<T>` and `Pin<T>`** are `Sendable` when `T` is, and a `LocalShared<T>` or a `LocalPin<T>` never is ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners), [03](03-handles-and-objects.md#pinning-for-c)). `Synchronized` types, `Future<T>` among them, always are ([below](#the-synchronized-contract)).
- **`~Sendable`** in a conformance list opts out a type that must stay on one thread although its fields could move, such as the id of an OpenGL texture or a window.
- **`unsafe Sendable`** promises, unchecked, that values of a type whose fields aren't all `Sendable` may be moved to other threads and shared with them ([10](10-errors-and-safety.md#unverified-promises)). Examples are a wrapper over a raw pointer into a thread-safe C library, and a handle to heap state that synchronizes itself, as a channel end is. It can't cover an object pointer or lock guard the type holds (above).

**`Sendable` is required of everything that code on one thread can reach from another:**

- a thread body's captures ([below](#what-a-thread-can-share));
- what a job system lends to its threads and hands back ([below](#the-librarys-promise));
- the contents of a `Synchronized` value, such as a queue's items or a `Future`'s result, except the raw pointers its `unsafe` code answers for ([below](#the-synchronized-contract));
- the value of a `Shared` whose owners or weak links cross threads ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners));
- every global that safe code reaches ([below](#global-state)).

**A `Channel`'s items needn't be `Sendable`.** The ends of one whose items aren't `Sendable` aren't either, so both stay on one thread.

## Lending work to other threads

A job system is a Rayo library whose safe API takes function values that borrow the caller's data, and runs them on its threads as **lent work**:

```swift
particles.forEachInParallel { p in                          // @sendable (mutable Particle) -> Void: not mutating, so any thread
    p.vel += gravity * dt
    p.pos += p.vel * dt
}
```

**These rules make what its users write race-free:**

- **Only `Sendable` values reach its threads** ([below](#the-librarys-promise)). A closure that captures an object's owner or weak pointer, even by reference, doesn't compile.
- **Closure kinds say how a function value may be called** ([05](05-protocols-generics-and-closures.md#closure-kinds)):
    - a non-`mutating` one by any number of threads at once;
    - a `mutating` one by one thread at a time, each call happening before the next;
    - a `consuming` one once.
- **Exclusivity holds across a call's arguments**, closures included, since a closure literal borrows what it captures for as long as the call has it. So the second `join` at the top of this chapter is rejected, as `f(&x, x)` is.
- **What a call begins ends with it**, by rule 5 ([02](02-views-and-dependencies.md#rule-5-the-callee-side)). A lock guard is released on the thread that took it ([below](#locks-mutex-and-rwlock)). So nothing a closure began on one thread is left for another.

Writing a shared place from a parallel loop's body is a type error:

```swift
particles.forEachInParallel { p in
    grid[cell(p.pos)] += p.mass     // error: writes 'grid', so the closure is 'mutating', but the loop runs it on many threads at once
}
```

With `grid` an `AtomicArray<Float>` ([below](#atomics-and-locks)), the body `grid.add(cell(p.pos), p.mass, .relaxed)` compiles: each write is an atomic add through a shared borrow.

### Scoped threads

**`Thread.scope`, at the top of this chapter, returns only when every thread its block spawned has finished.** It is `static func scope<R: ~Scoped>(_ body: consuming (mutable ThreadScope) -> R) -> R`. So a helper can take the scope as a `mutable ThreadScope` parameter. The block, called once, may write and move its captures, as `Mutex.lock`'s may ([05](05-protocols-generics-and-closures.md#closure-kinds)).

**`spawn` takes the closure by its concrete type and moves it into the scope**: `mutating func spawn(_ body: some consuming @sendable () -> Void)` ([05](05-protocols-generics-and-closures.md#closures-by-concrete-type-some-f)). A parameter of function type would get only a view of the literal, which dies at the end of its statement while the thread still runs it.

**The scope `s` absorbs what each closure borrows and carries, with the same kinds, until the block returns**, by rule 4 ([02](02-views-and-dependencies.md#rule-4-absorption)), since the scope's type is unsealed and scoped, as the library's promise requires ([below](#the-librarys-promise)). So nothing a spawned closure captures by reference can change or die meanwhile. A second `spawn` that writes `world.bodies`, or the block touching it after the first `spawn`, conflicts as two arguments of one call do:

```swift
Thread.scope { s in
    s.spawn { integrate(&world.bodies, dt: dt) }
    print(world.bodies.count)                               // error: 's' borrows 'world.bodies' exclusively until the block returns
}
```

### The library's promise

**Lending is the library's `unsafe` promise.** A scoped value, such as a closure that borrows the caller's locals, reaches another thread only through a library's `unsafe` code, which promises:

- **to move only `Sendable` values between threads.** The closures it takes are `@sendable`, and whatever it passes them is `Sendable`. Whatever it hands back from them to the lending thread is `Sendable` too: their results and the errors they throw. Each value it hands over is made and written before the receiving thread's first use of it, in the memory model's happens-before order ([below](#atomics-and-locks));
- **to call the value only as its kind allows**, each call of a `mutating` one happening before the next;
- **to keep it past the call it was given to only in a type that is unsealed and scoped**, as `Thread.scope`'s scope keeps what `spawn` is given ([02](02-views-and-dependencies.md#shallow-values)). So the value that keeps it absorbs what it borrows for as long as it is kept. While that call runs, a raw pointer to it may pass through any storage that only the library's `unsafe` code reads, such as a global work queue;
- **to have every other thread done with it by the time the borrows it carries may end**, every access they made through it happening before then. That time is when the call that lent them returns, as for `join`, or, for a value kept as above, the last use of the value that keeps it.

  So a keeping type is one of these:
    - one that safe code can make and drop, which declares a `deinit` that waits, making destroying it a use ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it));
    - one that only the library makes, like `Thread.scope`'s scope, where the library waits before the call that lends it returns.

By the first promise, a closure that returns or throws a lock guard taken on a worker, or an object made there, is rejected at the call, since neither is `Sendable`.

**The borrowed memory stays valid while it is lent.** The lender can't free it while the borrow lasts. A reset or an unregistration of its allocator panics while an open, the lender's or a worker's, still lends from it ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)).

**An unscoped `Sendable` value needs no such promise**, since it can't borrow.

### Thread-locals in lent work

**Thread-locals belong to the thread that runs the code.** Lent work that reads a `@threadlocal var`, or allocates through the current allocator, gets the running thread's copy. Work that the lending thread runs itself, as a join may, touches the lender's copy, and a conflict with an access the waiting lender holds panics on the ordinary access mark.

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

- **`Thread.loop`** runs its body once per item, on a thread that owns the `Receiver`, and parks between items.
- **`Thread.start`** runs its closure once.

### What a thread can share

**A closure that another thread may run after the call it was passed to returns is unscoped and `Sendable`**, such as a `@sendable` `Closure`. A thread's body is one such closure. Being unscoped, such a closure can't capture borrows. It owns its captures, which must be `Sendable`, and lists them ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)):

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

**`Runtime.startThread(_ body: owned Closure<consuming @sendable () -> Void>) -> Closure<consuming @sendable () -> Void>?` is the runtime's one primitive for starting a thread.** The new platform thread runs `body` with no Rayo frame below it. It returns `nil` once the thread has started, and returns `body`, unstarted, when the platform can't start a thread, or after shutdown ([below](#shutdown)). The call happens before the body begins.

**During startup it returns `nil` at once, and queues the thread until startup ends** ([below](#initialization-at-startup)). A queued thread that the platform can't start then panics.

**A library may also start threads through the platform's API with `import c`.** The start routine is then a C entry ([08](08-c-interop.md#c-entries-and-threads)). The runtime doesn't know that thread until it enters, so entering before startup ends or after shutdown panics, as for any C thread.

## Atomics and locks

**std's atomics, locks, queues, snapshots, one-time values and blocking primitives implement the `Synchronized` contract** ([below](#the-synchronized-contract)). So they may be shared across threads, and change through a shared borrow, as a global `let` of one does ([below](#global-state)).

**`Atomic<T>` holds a copyable, padding-free value of 1, 2, 4 or 8 bytes**, such as an integer, `Bool`, float, pointer or `Handle<T>`, since a compare-and-swap compares every byte ([04](04-types.md#plain-data-pod-and-bit-casts)). Each operation takes an explicit ordering, as in `counter.add(1, .relaxed)`, and is lock-free: none blocks or waits for another thread.

**Rayo uses the C++20 memory model.** The orderings `.relaxed`, `.acquire`, `.release`, `.acqRel` and `.seqCst` mean what they mean there. So does a data race, which safe code can't write ([above](#why-safe-code-cant-race)).

**An ordering is a `const` argument, and one the operation doesn't accept is a compile error:**

- a load takes `.relaxed`, `.acquire` or `.seqCst`;
- a store takes `.relaxed`, `.release` or `.seqCst`;
- a read-modify-write takes any of the five;
- a compare-and-swap's failure ordering is `.relaxed`, `.acquire` or `.seqCst`.

`AtomicArray<T>` is a fixed-size array of atomics.

**Creation happens before use.** Each of these happens before every use through a value that names what it made, however that value reached the using thread, even through a `.relaxed` atomic:

- creating a `Shared` value;
- registering an allocator;
- interning a `Name`.

The check each use makes synchronizes with the creation.

### Locks: `Mutex` and `RwLock`

**`Mutex<T>` owns its data, and reaching it requires locking**, in closure form or as a guard:

```swift
let log = Mutex(List<Message>())
log.lock { msgs in msgs.append(m) }      // closure form: lock takes 'consuming (mutable T) -> R', called once

var g = log.lock()                       // guard form: an owned, move-only, scoped MutexGuard<List<Message>>
g.value.append(n)                        // views of g.value depend on g
consume g                                // unlocks; otherwise its deinit unlocks at scope end

log.lock { msgs in
    log.lock { _ in }                    // panics: this thread already holds 'log'
}
```

- **The closure form calls the closure exactly once**, so it takes the most general closure kind, and the closure may move a captured local out, as the first one moves `m`. The closure's parameter isn't `keep`, so no view of the protected data outlives the lock ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)).
- **The guard form returns an exclusive guard from a shared `self`**, the `Synchronized` exception to dependency rule 3 ([02](02-views-and-dependencies.md#mutable-views)). A guard is scoped, so it can't be:
    - stored anywhere unscoped, such as a global, a `StablePool` or an object;
    - returned past the mutex it came from;
    - held across an `await`.
- **Relocking a `Mutex` that the same thread already holds panics**, in either form. That includes relocking from lent work that the lending thread runs while an outer frame of it holds the lock. So no thread ever gets a second exclusive view.
- **Guards have `@guard` types**, so a guard is released only on the thread that took it ([02](02-views-and-dependencies.md#lock-guards-are-released-on-the-thread-that-took-them)), and points only into the lock it came from ([below](#the-synchronized-contract)).

**`RwLock<T>` works like `Mutex`, with `read` (shared) and `write` (exclusive) in both forms.** Taking the write lock on a thread that holds either lock, or either lock on a thread that holds the write lock, panics. A read lock taken again on a thread that holds one is granted at once, even while a writer waits, since that writer can't proceed before the outer read ends.

### Queues and channels

- **Queues** have `pop() -> T?`, which doesn't block, and `waitPop() -> T`, which does. Single-producer and single-consumer queues check their single sides at run time. Overlapping calls on one side panic. Each call's check synchronizes with the previous call on that side, whichever thread made it. So the algorithm never sees two producers or two consumers at once, and sees successive ones in order.
- **`Channel<T>`** makes a queue that two **owned ends** share. `let (tx, rx) = Channel<Request>.make(capacity: 64)` returns a `Sender<T>` and a `Receiver<T>`. They are move-only, unscoped values that point to shared heap state, so `T` must be `~Scoped` ([02](02-views-and-dependencies.md#generic-code-and-scoped)).
    - **The ends aren't `Synchronized`.** `rx.pop()` and `rx.waitPop()` are `mutating`, so exclusivity makes the one `Receiver` the single consumer statically. `tx.push(_:)` is `mutating` too, so each `Sender` is one producer at a time.
    - **The shared state counts the ends that own it.** A sender queued inside its own channel is a cycle that dropping the `Receiver` breaks, since that destroys the queued items. Other cycles, such as a `Receiver` queued inside its own channel, leak.

### Snapshots, one-time values and waits

- **`Published<T: Frozen & Sendable>`** holds a value that any thread reads and replaces. `p.snapshot()` returns a new owner of the current value, a `Shared<T>`, adding one to its count without waiting. `p.publish(v)` swaps in a new value and drops its own owner of the old one, which whoever drops the last owner destroys ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)), so a snapshot taken before the swap stays valid.
- **`Once<T>`** is set once. Its `get()` lends a read-only `Borrow<T>?`, `nil` until the value is set.
- **Blocking primitives** are `Event`, `Condvar`, `Semaphore` and `Future`, whose waits park the thread ([below](#parking-and-waking-a-thread)). `g = cv.wait(consume g)` unlocks, parks, relocks after it wakes, and returns a new guard. `g` can be consumed only after the last use of every view derived from it, so no view of the protected data survives the unlock. The mutex is in the consumed guard's dependency set, so the wait borrows both the condvar and the mutex.

### The `Synchronized` contract

**A `Synchronized` type's non-`mutating` methods mutate only through the type's own synchronization.** The language defines this contract, which the types above share, as the marker protocol **`Synchronized`**. That property is what makes such a value safe to share across threads as a shared borrow, whether lent or held in a global `let` ([below](#global-state)). A `Synchronized` type:

- **is move-only** (the conformance implies `~Copyable`), so every thread synchronizes on the same memory;
- **holds no niche** ([04](04-types.md#optionals));
- **is derived, with no promise**, for these:
    - an inline array whose element type is `Synchronized`;
    - a struct or tuple with at least one stored field that is `Synchronized` or a `Shared` of a `Synchronized` value, and every other stored field one of those, or `Frozen`, `Sendable` and unscoped.

  The derived type's non-`mutating` methods can then change it only through those elements or fields, and a `Shared`'s value only through that value's own synchronization. So `Services(log: Mutex(…), config: Published(…), mixer: Shared(Mutex(AudioMixer())))` can be a `Shared`'s value ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners));
- **has unscoped contents that are `Sendable` or raw pointers**, which it hands to other threads: `Mutex<Span<T>>` and `Mutex<WeakPointer<T>>` are compile errors, and `Mutex<List<T>>` is fine when `T` is `Sendable`. So the type is itself `Sendable`. A raw pointer handed over this way, as by `Atomic<*T>` or an allocator's `Allocation`, is used only in `unsafe` code, which answers for what it points at ([10](10-errors-and-safety.md#what-unsafe-code-upholds));
- **keeps what its synchronization writes out of safe code's reach.** Every stored field that its non-`mutating` methods write is `unsafe` or itself `Synchronized`. So no safe access reads it with a plain load: not by name, reflection, `SoA` column, protocol witness, or derived `==` or `hash(into:)` ([05](05-protocols-generics-and-closures.md#conformances), [09](09-compile-time.md#reflection-and-access-control)). For the same reason it is never `Frozen` or `Pod` ([06](06-memory-and-allocators.md#frozen-types-with-no-interior-mutability), [04](04-types.md#plain-data-pod-and-bit-casts));
- **takes elements in and hands them out as owned values**, each handed out after, in happens-before order, the call that took it in, and lends views of them only as the next bullets allow;
- **grants a view only while no conflicting view of the same data is live, on any thread**: an exclusive guard or closure argument while no other view is live, and a shared one while no exclusive one is. Each view it grants happens after the end of every conflicting view it granted before. A request that would conflict with a view its own thread holds panics or blocks, and never succeeds, so a re-entrant lock can't satisfy the contract;
- **declares every guard it returns from a shared `self` `@guard`, and each guard points only into its lock**: the lock's own storage, or `.system` heap state that the lock points to and keeps allocated while the guard lives ([02](02-views-and-dependencies.md#lock-guards-are-released-on-the-thread-that-took-them));
- **lends a view of its interior only in one of two ways:**
    - under a lock, through a closure it runs or a `@guard` guard it returns, as `Mutex` and `RwLock` do;
    - as a read-only view of data that its non-`mutating` methods never write again, except through that data's own synchronization, and never free before the value itself is destroyed, as `Once.get()` lends;
- **is bitwise-movable whenever nothing borrows it.** The language moves a value only when nothing borrows it. An `unsafe Synchronized` conformance promises that the unborrowed value keeps no pointer to itself and has no address registered anywhere. Moving or destroying it stays sound even when a guard it returned is never destroyed ([10](10-errors-and-safety.md#aliasing-and-skipped-deinits)), as when the guard sits in a stale container. Its lock then stays held.

**Declaring a conformance to `Synchronized` requires `unsafe`**, because the compiler can't verify the implementation: `struct SpinQueue<T>(…): unsafe Synchronized { … }`, or `extension T: unsafe Synchronized {}` ([10](10-errors-and-safety.md#unverified-promises)).

### Parking and waking a thread

**A blocking primitive parks its waiting thread through the runtime**, which any `unsafe` code may call:

- `unsafe Runtime.park(on word: *UInt32, expected: UInt32, timeout: Int?) -> Bool` parks the calling thread on `word` if it still holds `expected`, until another thread wakes it or `timeout` nanoseconds pass, and returns `false` only when the timeout passed. It may also return early, so its caller checks its condition again. Its caller promises that `word` stays live and is accessed only atomically meanwhile.
- `unsafe Runtime.wake(on word: *UInt32, count: Int)` wakes up to `count` threads parked on `word`.

**A parked thread keeps everything it holds**, so its live borrows still count as uses of their allocators ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)).

## Global state

**Safe code has no unsynchronized mutable globals**, since a global is reachable from every thread. A bare global `var` needs `unsafe` to access.

```swift
let config = Published(GameConfig())           // global; safe from any thread
let godMode = Atomic(false)
@threadlocal var scratch = List<Int>()

func damageScale() -> Float { copy config.snapshot().value.damageScale }   // an owner that never waits, then a copy
func debugMenuSet(_ c: owned GameConfig) { config.publish(c) }      // readers see old or new, never torn

func grow() { scratch.append(0) }              // modify access to this thread's 'scratch'
func scan() {
    for x in scratch { grow(); use(x) }        // panics: read by the loop, modified by grow()
}
```

**Every global that safe code reaches has a `Sendable` type, except a `@threadlocal var`** ([above](#what-may-cross-threads-sendable)). A bare global `var` and an imported C variable may have any unscoped type, since every access to one is `unsafe` and answers for which threads touch it. Safe code can use:

- **`const`s, and `let`s of any `Sendable` type.** Code reaches one only through shared borrows, with no access checks, only the check that its initializer has run where the compiler can't prove it ([below](#initialization-at-startup)). What it holds changes only through its own synchronization: a `Synchronized` value's, such as an `Atomic`, `Mutex`, `Published` or `Once`, or a `Shared`'s count and its value's own ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners));
- **`@threadlocal var`s**: each thread has its own copy. `@threadlocal` marks only a `var`.

**A global is declared at a file's top level or as a static member of a type.** A variable declared directly in a function body is a local, and is never `static` or `@threadlocal`.

**A static stored `let`, `var` or `@threadlocal var` is never declared where one declaration stands for many instances.** Each instance would need its own, initialized in no one module's turn ([below](#initialization-at-startup)). Those places are:

- a generic type or an extension of one;
- a protocol extension;
- a type nested in any of these;
- a type or extension local to a function with several instantiations, such as a generic function, a function with a `some P` parameter or a method of a generic type.

A `static const` is evaluated at compile time for each instance.

- **Thread-locals need no synchronization.** But the static checker can't see a callee touching one, so each access is marked as a read or a change. A conflicting access panics, as `grow()` does above under the loop. The marks never synchronize with another thread. A view of a thread-local is a dynamic access under rule 6 ([02](02-views-and-dependencies.md#rule-6-dynamic-accesses)).
- **Each thread's copy lives until the thread's teardown.** Copies are initialized on their own thread, before it runs any other Rayo code, in the order globals are and under the same checks ([below](#initialization-at-startup)):
    - the startup thread's during startup, interleaved with the globals: the thread that runs `main`, or the one that calls `rayo_init`;
    - a thread's started with `Runtime.startThread`: before the body;
    - a C thread's when it attaches ([08](08-c-interop.md#embedding-rayo-in-a-c-program)).

**A thread's teardown destroys its copies and its objects, on that thread, once it has no other Rayo code to run.** That is when its body returns, at shutdown on the thread that shuts down ([below](#shutdown)), or when a C thread detaches. It runs these steps:

1. The thread's copies are destroyed in reverse order, except those of the prelude's modules and every module they import. Each copy is marked dead before its value is destroyed, so a `deinit` that touches it later in the teardown panics, whether the copy's own destruction runs that `deinit` or a later step does.
2. The thread's objects end ([03](03-handles-and-objects.md#destroying-an-object)).
3. A `deinit` of step 2 may make or leak another object of the thread, so that step repeats until a round leaves nothing. No object outlives its thread.
4. Those copies, the current allocator among them, are destroyed last, each marked dead first as in step 1.

**A thread that never tears down leaks what its copies and objects own**, as a C thread that exits without detaching does.

### Initialization at startup

```swift
let names = loadNames()      // runs before main, unless it can run at compile time
let table = buildTable()     // may read 'names'; reading a global declared after it is an error
```

**Initialization is eager and ordered.** `const`s are folded at compile time. A global `let` goes into read-only data, in every build, exactly when its initializer can run at compile time ([09](09-compile-time.md#running-code-at-compile-time-const)) and its value passes the **freezable** test ([09](09-compile-time.md#consts-that-reach-run-time)). A compile-time run of it that panics is a compile error, as for a `const`. One that exceeds the toolchain's evaluation limits leaves the global to startup, which computes the same value. No global is destroyed ([below](#shutdown)) or consumed ([01](01-values-and-ownership.md#what-can-be-moved-from)), other than a thread-local's copy, which ends in its thread's teardown.

**Every other global is initialized at startup**, one module at a time, each module's declarations in source order. **Startup** runs before `main`, or in `rayo_init()` when a C program embeds Rayo ([08](08-c-interop.md)). The next module is always the first in the build's list ([09](09-compile-time.md#what-a-build-declares)) whose imports are all initialized. A module outside the prelude's modules and every module they import counts all of those as imports ([11](11-compilation-model.md#the-prelude)).

- **Static check.** Reading a global that isn't initialized yet, directly or through any chain of direct calls from the initializer, is a compile error. A direct call is any whose callee is known statically, including those the language makes for the code ([05](05-protocols-generics-and-closures.md#functions-and-closures)). A requirement call inside an imported generic body isn't one: the module's check, made against interfaces alone, can't see it ([11](11-compilation-model.md#type-checking-is-local)). Imports form no cycle ([11](11-compilation-model.md#no-import-cycles)), so a chain of calls the check follows ends in the initializer's own module, at its own global or one declared after it.
- **Run-time check, in every build.** For calls the static check doesn't follow (closures, `any P`, function pointers, and requirement calls inside imported generic bodies), reading a global before its initializer has finished panics.
- **Read-only data.** A global in read-only data counts as initialized, for both checks, only once startup reaches its declaration, so whether its compile-time run fits the toolchain's limits never changes what a program does ([11](11-compilation-model.md#what-the-language-leaves-open)).
- **No other threads during startup.** Initialization is single-threaded. The last initializer's return happens before every later entry into Rayo code on another thread, a queued thread's start included.
    - A thread started with `Runtime.startThread` during startup is queued until then ([above](#starting-a-thread-runtimestartthread)).
    - A wait that would park until another thread acts panics. `Thread.sleep` and waits with a timeout depend on no other thread, so they don't panic, and a wait whose condition already holds returns at once.
- **Entry.** Entering Rayo code from C panics, in every build, before startup has finished, and from a C thread after shutdown ([below](#shutdown)). The exception is a **nested entry**: one with a Rayo frame below it on its thread, on any of the thread's stacks.
    - During startup only the startup thread has one. An initializer may call C that calls an `@export` or `@c` function back. That entry is let in, while the initialization check still guards every global the callback reads.
    - After shutdown such an entry is let in as before.

### Shutdown

A program's **`main`** takes no parameters, and returns `Void`, `Never`, or an `Int32` that becomes the process's exit status. The runtime shuts down when `main` returns, or when a C program that embeds Rayo calls `rayo_shutdown()` ([08](08-c-interop.md#embedding-rayo-in-a-c-program)).

**At shutdown, the thread that shuts down tears down, and then entry closes:**

1. The thread's teardown runs ([above](#global-state)), so a `deinit` that flushes or closes something runs, and sees that thread's copies, the current allocator included.
2. Entry closes: from then on, an entry from C with no Rayo frame below it on its thread panics ([above](#initialization-at-startup)), and `Runtime.startThread` returns its body unstarted ([above](#starting-a-thread-runtimestartthread)).

- **Other threads don't tear down at shutdown.** When `main` returns, the process exits, ending them where they stand. In a C program that embeds Rayo, a thread that `Runtime.startThread` started still tears down when its body returns, and an attached C thread can no longer detach ([08](08-c-interop.md#embedding-rayo-in-a-c-program)).
- **No global is destroyed**, not even at shutdown, since a thread still running may read one. Only a thread-local's copies end, each in its own thread's teardown.

## `task` functions: explicitly stepped coroutines

**A `task func` can suspend at `await`, and continue when its owner steps it.** Calling one returns a **task**, the value its owner steps:

```swift
task func openDoor(_ door: owned Handle<Door>) with (game: mutable Game) {
    guard let d = game.doors[door] else { return }
    game.audio.play(d.creakSound, at: d.pos)
    game.doors[door]?.state = .opening
    await seconds(0.5)
    game.doors[door]?.state = .open
    await until { [copy door] game in game.playerDistance(to: door) > 5 }   // game is lent to the condition on each poll
    await closeDoor(door)                   // awaiting a sub-task runs it inline, with its state nested
}
```

**Each step runs the task to the next `await` whose awaitable isn't done**, whenever its owner steps it. Tasks are stackless coroutines.

### Semantics

- **A task is a value.** Calling a `task func` runs nothing: it returns the task. A task is its **state**: a struct whose layout the compiler computes. Its size is known statically, so a task never allocates on its own. It is move-only, and it borrows nothing, since its parameters are unscoped and no borrow is live across an `await` (below). It lives wherever its owner puts it: a local, a field, a parent task's state when awaited as a sub-task, or a task set ([below](#running-tasks)).
- **No borrow and no dynamic access may be live across an `await`.** That means none of these may be live there:
    - a scoped value ([02](02-views-and-dependencies.md#where-a-scoped-value-can-go));
    - a binding or pattern part that borrows a place;
    - a borrowed place the statement has already worked out when it suspends, such as an assignment's left side or an argument place before the `await`, unless it lies in the task's parameters or owned locals and is reached through stored fields and indices without reading an optional.

  `d` above borrows the door and ends before the first `await`. So using it after the `await` is a compile error, and code there reads `game.doors[door]` again.

  **A place in the task's own state is worked out again on resuming**, from the index values already computed, since only the task's body reaches that state. So `total += await next()` on a local works, while `game.score += await pointsFor(n)` is a compile error, and `let p = await pointsFor(n)` comes first.

  **The resume parameter is exempt**, since each step lends it anew.
- **Locals that are live across an `await`, and parameters, are stored in the state.** So they must be owned: every task parameter is declared `owned` ([01](01-values-and-ownership.md#parameters)), and its type is unscoped. A `task func` method is `consuming` or `static`, so `self` is owned too, and its type is unscoped.
- **The resume parameter.** The `with (...)` clause declares the task's one **resume parameter**, whose type is its `Context` ([below](#awaitables)), or `Void` when there is none. It is declared `mutable`, since the owner only lends it for the step and every awaitable's `poll` takes it `mutable`. It has no default value. The owner passes it in fresh at every step, as `scripts.step(&game)` does ([below](#running-tasks)).
- **What a task can await.** In a task whose `Context` is `C`, `await x` needs an `Awaitable` whose `Context` is `C`, polled with the task's resume parameter, or `Void`, polled with `()`. The operand is checked expecting an `Awaitable` whose `Context` is `C`. So a generic parameter that appears only in the operand's `Context` is bound to `C` before the operand's arguments are checked, as in `await seconds(0.5)`. A closure argument then gets its parameter types from that binding, as in `await until { [copy door] game in … }` above. `await` takes its operand as an `owned` argument is taken ([01](01-values-and-ownership.md#moving-values-out)): it moves into the task's state and is polled there, so `let mesh = await f` consumes a local future `f`.
- **Only the task's own body suspends.** `await` appears only in a `task func`'s own body. It can't appear in:
    - any other function;
    - a closure literal, a nested function, or a local type's or extension's members inside a task, since those are called, not stepped;
    - a `defer` block, which also runs when the task is destroyed.
- **Destroying a suspended task cleans it up.** Cancelling it, or dropping it or the task set that holds it, destroys its state as leaving every open scope would. The `deinit`s of its live locals and its live `defer` blocks run, in the usual order ([10](10-errors-and-safety.md#cleanup)), and no other code does. That happens outside any step, with no resume parameter. So a `defer` that is live across an `await` may use only what exists without a step: the state's parameters and owned locals, and the globals any code reaches, not the resume parameter.
- **A finished task stays finished.** Once its `poll` has returned `.done` or `.failed`, its result has moved out and its locals are destroyed, so destroying it runs nothing, and polling it again panics ([10](10-errors-and-safety.md#what-panics)).
- **A task never holds itself.** Its state never contains a state of its own type, as it would if its body awaited a call of itself directly or through other `task func`s ([04](04-types.md#structs)); recursion goes through an owner, such as a `Box`.
- **Results and errors.** A task returns and throws as a function does: `task func loadLevel(_ id: owned LevelId) with (ctx: mutable Loader) throws(LoadError) -> Level`. In another task, `let level = try await loadLevel(id)` yields the result or propagates the error.

### Awaitables

**Whatever a task waits on is an awaitable**: a value the task polls at each step until it reports that it is done.

```swift
protocol Awaitable {
    associatedtype Context
    associatedtype Output = Void
    associatedtype Failure: Error = Never
    mutating func poll(_ ctx: mutable Context, _ waker: Waker) -> Poll<Output, Failure>
}

enum Poll<Output, Failure: Error> {
    case done(Output)
    case failed(Failure)
    case pending          // poll me again at the next step
    case waiting          // a stepper may skip me until someone calls the waker I stored
}

struct Waker(                     // made by whatever steps the task
    let target: WeakShared<any WakeTarget>,
    let id: UInt64,
): Copyable {                     // Sendable, derived: it holds only a weak link and an id
    func wake() { … }             // any thread, including C callbacks; nothing once the target is gone
}

protocol WakeTarget: Synchronized {   // reached only by shared access, so it changes only through its own synchronization
    func wake(id: UInt64)             // called from any thread, C callbacks and real-time threads included
}
```

**`await x` evaluates to `x`'s `Output` once it is done.** For the dependency rules, it is the `x.poll(&ctx, waker)` call that returned `.done`, with `x` a temporary of its statement. So the value, and an error that `try await` throws, depend, exclusively, on each of these:

- the resume parameter;
- `x`'s storage, unless `x` is a `task func`'s call. That task's result can view nothing its state owns, as no function's result views what its `owned` parameters or locals own ([02](02-views-and-dependencies.md#rule-5-the-callee-side)).

An awaitable whose `Failure` isn't `Never` is awaited with `try await`, and `.failed(e)` throws `e` there ([10](10-errors-and-safety.md)). A `task func` is an awaitable of its return and error types.

**Only its owner's `step` resumes a task, but a step needn't visit every task.**

- A **pending** task is polled every step.
- A **waiting** task isn't. Its awaitable has handed the `Waker` to whatever will complete it, such as a `Future`, an I/O completion or a timer wheel. The next `step` after a wake resumes it.

**`wake()` upgrades its weak link and calls the target's `wake(id:)` through the new owner** ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)). So reaching the target takes no lock and never waits, though `wake(id:)` itself may. Waking a destroyed target does nothing. When every other owner of the target drops while `wake()` holds the one it upgraded, `wake()` drops the last owner, and destroys the target on the waking thread.

**`poll` returns a correct result whenever it is called**, since a poll may still come at any step, woken or not. A wake is only a hint: it may reach a target for an id it no longer runs, since a `Waker` may outlive its task.

**std's awaitables include these:**

- `until { ctx in cond }`;
- `Future<T>`, whose `Output` is `T`;
- **timed waits**: `func seconds<C: TimeSource>(_ s: Double) -> Seconds<C>`, whose `Context` `C` gives the program's own time through `TimeSource`'s `var now: Double { get }`.

So `openDoor`'s `seconds(0.5)` counts simulation time once the game declares `extension Game: TimeSource { var now: Double { copy simulationTime } }`.

**A suspended task's awaitable is stored in its state, so it can't hold a borrow either.** So `until`'s condition receives the resume parameter as its argument on every poll. `until` takes the condition by concrete type and moves it in: `func until<C, F>(_ cond: owned F) -> Until<C, F> where F: (mutable C) -> Bool, F: ~Scoped` ([05](05-protocols-generics-and-closures.md#closures-by-concrete-type-some-f)). It stores the condition by value in the task's state, never boxed, with its captures counting against the state's size. Being unscoped, the condition owns and lists its captures, as `[copy door]` does. A condition that captures the resume parameter, or any other borrow, is rejected: `await until { game.isOver }` is a compile error, and `until { game in game.isOver }` takes the parameter instead.

### Running tasks

```swift
var scripts = TaskSet<Game>(capacity: 512)           // resume context type: mutable Game
let t = scripts.start(openDoor(frontDoor))           // returns Handle<TaskSlot>
scripts.cancel(t)                                    // runs live locals' deinits and live defers, or, unstepped, destroys its parameters

scripts.step(&game)                                  // wherever the program steps: resumes pending and woken tasks once each
```

**std's `TaskSet` takes ownership of each task it starts**, through `TaskSet.start<A: Awaitable>(_ work: owned A) where A.Context == C, A.Output == Void, A.Failure == Never, A: ~Scoped`. A `TaskSet` isn't `Sendable`, since its type doesn't show its tasks' types. So it and its tasks stay on one thread, and the tasks needn't be `Sendable`. A task is `Sendable` when everything in its state is.

