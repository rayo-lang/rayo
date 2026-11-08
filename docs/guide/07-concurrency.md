# 7 · Concurrency

The game's enemies now number in the thousands. Each frame, they move, and the game needs their total health. Chapter 5 used a pool where lasting handles mattered; this update uses a list so the job system can split its elements among cores. In C++ an ordinary parallel loop can compile even when it races:

```cpp
float total = 0;
std::for_each(std::execution::par, enemies.begin(), enemies.end(), [&](Enemy& e) {
    e.pos += e.vel * dt;
    total += e.hp;                        // every thread writes 'total'
});
```

The compiler says nothing about the race. A frame now and then reports the wrong total. In Rayo, each parallel worker can change only its own enemy, and a separate reduction adds up their health:

```swift
import std.jobs                                         // join, forEachInParallel, parallelReduce

func integrate(_ enemies: mutable List<Enemy>, dt: Float) {
    enemies.forEachInParallel { e in                    // runs the body on many threads at once
        e.pos += e.vel * dt                             // fine: each call changes only the enemy it was given
    }
}

func totalHp(_ enemies: List<Enemy>) -> Float {
    enemies.span.parallelReduce(Float(0), combine: +) { sum, e in sum + e.hp }
}
```

`parallelReduce` splits the work and merges the results: each job sums its own slice from `0`, and `+` combines the partial sums. Writing `total` from the loop's body doesn't compile in Rayo. The borrowing rules you already know ([Borrowing](03-borrowing.md)) also keep a worker from changing an enemy it wasn't given.

## Lending work to other threads

```swift
join({ integrate(&world.enemies, dt: dt) },             // may run both closures at once, and returns when both are done
     { mix(&world.audio) })                             // fine: each closure writes a different field

join({ integrate(&world.enemies, dt: dt) },
     { drawRadar(world.enemies) })                      // error: one closure reads 'world.enemies' while the other writes it
```

`std.jobs` is a **job system**: it runs closures on a pool of threads. The closures in `join` borrow parts of `world` for the length of the call, and `join` finishes them before it returns. This is **lent work** ([07](../spec/07-concurrency/thread-work.md#lending-work-to-other-threads)).

The ordinary law of exclusivity still applies. The first `join` works because each closure names a different field of `world`, and a closure captures only the places its body names ([05](../spec/05-protocols-generics-and-closures/functions-and-closures.md#capturing-places)). The second fails because one closure changes `world.enemies` while the other reads it. They are two arguments of one call, much like two conflicting borrows in a single-threaded call.

**A closure's kind says how a job system may call it** ([05](../spec/05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)). The compiler works out the kind from the body:

- a non-`mutating` closure only reads its captures, so any number of threads may run it at once;
- a `mutating` closure writes a capture, so only one thread at a time may run it;
- a `consuming` closure moves a capture out, so it runs at most once.

`forEachInParallel` may run its body on several threads at once, so its closure cannot change a captured variable. `join` runs each closure once and can accept one that changes its own capture. That difference rejects this attempt to add to `total`:

```swift
var total: Float = 0
enemies.forEachInParallel { e in
    total += e.hp       // error: writes 'total', so the closure is 'mutating', but the loop runs it on many threads at once
}
```

The body can change the element it was given: each call gets a different one. To combine results, use a reduction such as `parallelReduce`, or an atomic ([below](#atomics)). Changes that might touch another element, such as damaging an enemy's target, happen after the call returns and its borrows end.

The job system's own `unsafe` code promises to call each closure only as its kind allows, and to finish before the data it borrows goes away ([07](../spec/07-concurrency/thread-work.md#the-librarys-promise)). Calls to it remain safe code.

### Scoped threads

```swift
ThreadScope.run { s in
    s.spawn { integrate(&world.enemies, dt: dt) }       // runs on another thread
    mix(&world.audio)                                   // runs on this thread meanwhile
    print(world.enemies.count)                          // error: 's' borrows 'world.enemies' exclusively until the block returns
}                                                       // every spawned thread has finished here
```

**`ThreadScope.run` starts threads that may borrow the caller's locals** ([07](../spec/07-concurrency/thread-work.md#scoped-threads)). It returns only when every thread its block spawned has finished, so no thread outlives what it borrows.

**`spawn` hands its closure to the scope `s`, and `s` holds what the closure borrows until the block returns.** So code in the block, or a second `spawn`, that touches `world.enemies` conflicts, as a second argument of one call would.

**A panic in a spawned thread waits for the others, then carries on in the caller.** Chapter 1 showed a panic abandoning the work in progress. Here it abandons only the spawned closure's work, destroying what the closure owns, while the block and the other threads run on. Once every thread has finished, `ThreadScope.run` carries the panic on as if the block itself had panicked ([07](../spec/07-concurrency/thread-work.md#scoped-threads)). So the scope still never returns before its threads are done, even when one fails. The job system's `join` and parallel loops treat a panic in their closures the same way.

## What may cross threads: `Sendable`

```swift
struct Hud(var root: WeakPointer<Widget>)               // not Sendable: holds a weak pointer
struct GLTexture(let id: UInt32): ~Sendable             // opts out: the id is valid only on the GL thread
```

The `Enemy` from chapter 5 can cross to another thread because its fields can, including its handle to a player. `Hud` cannot: it holds a weak pointer to a menu widget from that chapter, and a weak pointer belongs to its object's home thread. The marker protocol **`Sendable`** records this distinction. Only a `Sendable` value may move to another thread or be lent to one for a call ([07](../spec/07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).

The compiler works out `Sendable` from what a type holds, as it does for `Copyable`:

- **A struct, enum, tuple or array is `Sendable` when everything it holds is.** std's containers follow their elements, so `List<Enemy>` is `Sendable`, and `List<WeakPointer<Enemy>>` isn't.
- **Object pointers never are.** `UniquePointer`, `WeakPointer` and anything that holds one stay on the object's home thread ([Handles and objects](05-handles-and-objects.md)).
- **`Shared<T>` is `Sendable` when `T` is, and `LocalShared<T>` never is** ([06](../spec/06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)).

`GLTexture` opts out with `~Sendable`. Its `UInt32` field could cross threads, but the id it holds is meaningful only on the GL thread. A wrapper over a thread-safe C library's pointer can instead declare `unsafe Sendable`, making a promise the compiler cannot check ([10](../spec/10-errors-and-safety/unsafe-code.md#unverified-promises)).

**Lent work captures only `Sendable` values, even when it only borrows them.** A job system takes its closures as a **`@sendable` function type**, which accepts only closures whose captures are all `Sendable`. `forEachInParallel`'s body has the type `@sendable (mutable Enemy) -> Void`:

```swift
func drawMarkers(_ enemies: mutable List<Enemy>, _ hud: Hud) {
    enemies.forEachInParallel { e in
        mark(hud, at: e.pos)        // error: 'Hud' isn't Sendable, so lent work can't capture it
    }
}
```

**Code that uses a value that isn't `Sendable` runs on the thread that owns it**, such as in a plain loop after the parallel one.

## Shared mutable state

**Data that several threads change through shared borrows lives in a `Synchronized` type** ([07](../spec/07-concurrency/synchronization.md#atomics-and-locks)). A **`Synchronized`** type changes only through its own synchronization, such as a lock or atomic operations. So a shared borrow of it is enough to change it, from any thread.

**Lent work that changes data through a `mutable` borrow needs no lock.** Exclusivity already keeps the threads apart, since each closure that changes data has it to itself.

### Locks: `Mutex` and `RwLock`

```swift
let deaths = Mutex(List<Vec3>())
enemies.forEachInParallel { e in
    if e.hp <= 0 {
        deaths.lock { list in list.append(copy e.pos) }   // fine: one thread at a time holds the list
    }
}

var g = deaths.lock()                    // a MutexGuard<List<Vec3>>
g.value.append(copy boss.pos)
_ = g                                    // unlocks now; otherwise the end of the scope does

deaths.lock { _ in
    deaths.lock { _ in }                 // panics: this thread already holds 'deaths'
}

let nav = RwLock(NavGrid())
let route = nav.read { grid in findPath(grid, from: start, to: goal) }   // many readers at once
nav.write { grid in grid.block(cellOf(crate.pos)) }                       // one writer, and no readers meanwhile
```

**`Mutex<T>` owns its data, and you reach the data only by locking it** ([07](../spec/07-concurrency/synchronization.md#locks-mutex-and-rwlock)).

**The closure form locks, runs the closure once, and unlocks.** The closure can't keep a view of the data, so nothing reaches the data once the lock is released.

**Locking doesn't make a closure `mutating`.** `lock` is a non-`mutating` method, so a body that only locks `deaths` still runs on many threads at once.

**The guard form returns a guard, which holds the lock for as long as it lives.** `_ = g` releases it early, and shows where the lock ends.

**`_ =` drops a value on purpose.** Rayo rejects any value that code never uses, unless its type is `Void`, because an ignored result is usually a bug, such as an error nobody handled. So code that has no use for a value, such as the `Thread` that `Thread.start` returns below, drops it with `_ =` ([05](../spec/05-protocols-generics-and-closures/functions-and-closures.md#unused-values)).

**A guard is scoped.** It can't be stored in a global or an object, returned past the mutex it came from, or held across an `await` ([below](#stepped-tasks)).

**A guard isn't `Sendable`, so it's released on the thread that took it**, as many platform mutexes require ([02](../spec/02-views-and-dependencies/dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)).

**Locking a `Mutex` that the thread already holds panics**, in either form. So no thread ever gets a second exclusive view of the data.

**`RwLock<T>` works like `Mutex`, with `read` for shared access and `write` for exclusive access**, each in both forms.

**Taking the write lock on a thread that holds either lock panics**, and so does taking either lock on a thread that holds the write lock.

**A panic that abandons a `Mutex`'s closure or guard poisons the lock.** The panic still releases the lock, but the list it was changing may be half-changed. So from then on, locking `deaths` panics unless the program resets the lock, and no other thread mistakes the half-changed list for a whole one ([07](../spec/07-concurrency/synchronization.md#locks-mutex-and-rwlock)).

### Atomics

```swift
let spawned = Atomic(0)
spawned.add(1, .relaxed)                 // through a shared borrow, from any thread

func countCrowds(_ enemies: mutable List<Enemy>, into cells: AtomicArray<Int>) {
    enemies.forEachInParallel { e in
        cells.add(cellOf(e.pos), 1, .relaxed)     // fine: an atomic add, through a shared borrow of 'cells'
    }
}
```

**`Atomic<T>` holds a copyable value of 1, 2, 4 or 8 bytes**, such as an integer, a `Bool`, a float or a handle ([07](../spec/07-concurrency/synchronization.md#atomics-and-locks)). Each operation is lock-free: none blocks or waits for another thread. So an 8-byte one, such as `spawned`, an `Atomic<Int>`, builds only for a target with lock-free 64-bit atomics. Every 64-bit target has them, and some 32-bit ones don't.

**The value must be padding-free: its layout has no padding bytes**, since a compare-and-swap compares every byte, padding included.

**Every operation names its memory ordering.** The orderings are C++20's: `.relaxed`, `.acquire`, `.release`, `.acqRel` and `.seqCst`.

**An ordering is a compile-time argument, so one the operation doesn't accept is a compile error**, such as `.release` on a load.

**`AtomicArray<T>` is a fixed-size array of atomics**, so many threads can add into one grid at once.

### The `Synchronized` contract

**`Mutex`, `RwLock`, the atomics and std's queues share one contract: the marker protocol `Synchronized`** ([07](../spec/07-concurrency/synchronization.md#the-synchronized-contract)).

**A `Synchronized` type's non-`mutating` methods change it only through its own synchronization.** It lends its data only under a lock, or once nothing writes that data again.

**A `Synchronized` type is move-only, so every thread synchronizes on the same memory.** It is also always `Sendable`.

**A struct whose fields are all `Synchronized` is `Synchronized` too.**

**To declare `Synchronized` on a type of your own, such as a lock-free queue, write `unsafe Synchronized`**, since the compiler can't check the implementation.

## Threads that outlive the caller

```swift
var level = loadLevel()
let bounces = 3
_ = Thread.start(name: "bake") {
    bakeLighting(level, bounces: bounces)                               // error: unlisted captures; a thread body can't borrow them
}
let bake = Thread.start(name: "bake") { [move level, copy bounces] in   // fine: the thread owns 'level', and a copy of 'bounces'
    bakeLighting(level, bounces: bounces)
}
loadAudio()                                                             // runs on this thread meanwhile
bake.join()                                                             // waits until the bake has finished
```

**A thread started with `Thread.start` may run after the function that started it returns** ([07](../spec/07-concurrency/thread-work.md#what-a-thread-can-share)). So its body can't borrow anything: it must own what it captures.

**A thread's body is an unscoped closure: it owns its captures, so it can outlive the code that made it** ([05](../spec/05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)). Every capture must also be `Sendable`.

**An unscoped closure lists its captures, and says how each one gets in.** `[move level]` moves the level into the closure, so the function can't use it afterwards. `[copy bounces]` copies a copyable value, which stays usable outside.

**`Thread.start` returns a `Thread<R>`, where `R` is what the body returns, and `join()` waits for the thread to end and returns that value** ([07](../spec/07-concurrency/thread-work.md#joining-a-thread)). The bake returns nothing, so `bake` is a `Thread<Void>`. A thread that computes something hands it back through `join()`, as this one does with a checksum of some bytes it owns:

```swift
let hashing = Thread.start { [move bytes] in crc32(bytes) }   // a Thread<UInt32>
let crc = hashing.join()                                      // waits, then returns the body's UInt32
```

**If a panic ended the thread, `join()` carries it on in the joining thread**, as `ThreadScope.run` does for its threads.

**Dropping a `Thread` detaches the thread: it runs on by itself, and nothing can wait for it any more.** Its result, if any, is dropped when the thread ends. Rayo rejects an unused value, so code that never joins a thread drops its `Thread` with `_ =`, as below. A detached thread still running when `main` returns ends with the program.

**To hand a thread data that other threads also use, give it a weak link to a `Shared` value** ([03](../spec/03-handles-and-objects.md#sharing-across-threads)). A `WeakShared` is copyable, and `Sendable` when the value is. The thread upgrades it each time it needs the value:

```swift
let mixer = Shared(Mutex(AudioMixer()))
let m = mixer.weak()                                              // a WeakShared<Mutex<AudioMixer>>
_ = Thread.start { [copy m, copy clip] in                         // '_ =' detaches the thread: nothing joins it
    if let mx = m.upgrade() { mx.value.lock { $0.play(clip) } }   // one more owner while 'mx' lives
}
```

**Threads, locks and job systems are library code, not language features** ([07](../spec/07-concurrency.md)). The runtime's one primitive for starting a thread is `Runtime.startThread`, and a job system of your own can start its workers with it ([07](../spec/07-concurrency/thread-work.md#starting-a-thread-runtimestartthread)).

### Queues and channels

```swift
func startRenderer() -> (Thread<Void>, Sender<Shared<Snapshot>>) {
    let (tx, rx) = Channel<Shared<Snapshot>>.make(capacity: 3)
    let render: Thread<Void> = Thread.start(name: "render") { [move rx] in   // the thread owns the receiver
        for snapshot in &rx { draw(snapshot) }                               // waits for each snapshot in turn
    }
    return (render, tx)                                                      // the simulation keeps the sender
}
```

**A `Channel` hands items from one thread to another through two owned ends, a `Sender` and a `Receiver`** ([07](../spec/07-concurrency/synchronization.md#queues-and-channels)).

**The render thread owns the `Receiver`, and takes one item at a time from it in a loop.** Each pass calls `receive()`, which **parks** the thread between items: it sleeps until the next item comes. The `&` in `&rx` is there because receiving changes the `Receiver`.

**The loop ends once every `Sender` is gone**, after the render thread has drawn every snapshot sent before. The channel is then **disconnected**, and `receive()` returns `nil` instead of parking for ever ([07](../spec/07-concurrency/synchronization.md#disconnected-channels)). So the simulation stops the render thread by dropping its sender, and then joins it:

```swift
let (render, var tx) = startRenderer()
while running {
    step(&world)
    _ = tx.send(Shared(world.snapshot()))     // '_ =': if the render thread is gone, the snapshot is dropped
}
_ = tx                                        // drops the sender: the render loop ends
render.join()                                 // waits for the last frame
```

**The channel holds at most three snapshots, its capacity.** When the simulation runs ahead and three are already waiting, `send` parks it until the render thread takes one.

**`send` returns a `Result`, since the other side may be gone.** Once the `Receiver` is dropped, sending fails, and the error hands the snapshot back rather than losing it. Rayo rejects an unused value, so the simulation, which has no use for a snapshot nobody will draw, drops the result with `_ =`.

**A panic on either side disconnects the channel too.** Unwinding destroys the ends the panicking thread owns, as it destroys everything else. So a render thread that panics makes each later `send` fail, and `render.join()` then carries the panic on in the simulation. If the simulation panics, its sender is destroyed, and the render loop ends instead of waiting for ever.

**The ends are move-only.** `Sender<T>` and `Receiver<T>` are `Sendable` when `T` is, so each end can move to the thread that uses it. `tx.share()` makes another `Sender` of the same channel, for a second producer.

**Exclusivity makes the one `Receiver` the single consumer.** Its `receive()` is `mutating`, so the compiler checks that one thread at a time consumes, at no run-time cost. `send` is `mutating` too, so each `Sender` is one producer at a time.

**std's queues, such as `MpscQueue` and `SpscQueue`, are `Synchronized`**, so a global `let` of one serves any thread.

**`pop()` returns `nil` at once when the queue is empty, and `waitPop()` parks the thread until an item comes.** A queue is never disconnected, since every thread only borrows it, so nothing tells it the last producer is done. When a consumer needs to know that, use a channel.

**A queue with a single producer or a single consumer checks that side at run time**, and overlapping calls on it panic.

## Global state

```swift
let config = Published(GameConfig())     // any thread reads it, and publish swaps in a new one
let spawned = Atomic(0)
@threadlocal var scratch = List<Int>()   // each thread has its own copy
var frames = 0                           // a bare global 'var'

func tick() {
    spawned.add(1, .relaxed)             // fine: changes through its own synchronization
    scratch.append(0)                    // fine: changes this thread's copy
    frames += 1                          // error: accessing a bare global 'var' needs 'unsafe'
}
```

**Safe code has no unsynchronized mutable globals**, since every thread can reach a global ([07](../spec/07-concurrency/global-state.md#global-state)).

**A global `let` that safe code uses has a `Sendable` type.** Every thread reads it through shared borrows, with no access checks. It changes only through its own synchronization: a `Synchronized` value it holds, or a `Shared`'s count.

**A `Published` holds a value that any thread reads, and that `publish` replaces.** A reader sees the old value or the new one, never a mix of the two.

**A `@threadlocal var` gives each thread its own copy.** The compiler can't see a callee touching it, so each access takes a run-time mark, and a conflicting access panics as an object's does.

**A bare global `var` can be accessed only in `unsafe` code**, which answers for which threads touch it ([C and compile time](08-c-and-compile-time.md)). To count frames safely, make the counter `let frames = Atomic(0)`, or a `@threadlocal var` when each thread counts its own.

**Globals are initialized before `main`, one module at a time, in source order, on one thread** ([07](../spec/07-concurrency/global-state.md#initialization-at-startup)). A `@threadlocal var` is the exception: each thread initializes its own copy, on that thread, before it runs any other code.

**Reading a global before it is initialized is a compile error where the compiler can see it, and a panic where it can't.**

## Stepped tasks

```swift
task func openDoor(_ door: owned Handle<Door>) with (game: mutable Game) {
    guard let d = game.doors[door] else { return }
    game.audio.play(d.creakSound, at: d.pos)
    await seconds(0.5)                                     // suspends here; a later step resumes
    game.audio.play(d.slamSound, at: d.pos)                // error: 'd' borrows 'game.doors' across an 'await'
    game.doors[door]?.state = .open                        // fine: looks the door up again
}

var scripts = TaskSet<Game>(capacity: 512)
_ = scripts.start(openDoor(frontDoor))                     // calling openDoor runs nothing: it returns the task
scripts.step(&game)                                        // resumes pending and woken tasks once each
```

**A `task func` can suspend at `await`, and continues when its owner steps it** ([07](../spec/07-concurrency/tasks.md#task-functions-explicitly-stepped-coroutines)). It suits a script that spans frames, and it never runs on its own.

**Calling a `task func` runs nothing: it returns the task**, a value that its owner keeps and steps.

**A task is a value whose size the compiler knows, so it never allocates on its own.** Its parameters are `owned`, and the locals it keeps across an `await` live inside it.

**No borrow lives across an `await`**, since between steps the task holds only what it owns ([07](../spec/07-concurrency/tasks.md#semantics)). So after an `await`, look a borrowed value up again.

**The `with` clause names the resume parameter, which the owner lends anew at every step.** So the task never holds it between steps, and it may be used on both sides of an `await`.

**A `TaskSet` owns the tasks it starts, and steps them together.** It isn't `Sendable`, so it and its tasks stay on one thread.

## In the spec

- [07 Concurrency](../spec/07-concurrency/race-freedom-and-sendable.md#why-safe-code-cant-race): the four ways two threads can reach the same memory, and why safe code can't race.
- [07 The library's promise](../spec/07-concurrency/thread-work.md#the-librarys-promise): what a job system's `unsafe` code promises, how a panic in lent work reaches the lender, and thread-locals in lent work.
- [07 Joining a thread](../spec/07-concurrency/thread-work.md#joining-a-thread): `join()`, detaching, and what a thread's panic does.
- [07 Sendable](../spec/07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable): every rule that derives `Sendable`, and where it is required.
- [07 Atomics and locks](../spec/07-concurrency/synchronization.md#atomics-and-locks): memory orderings, `Mutex` and `RwLock`, queues, channels, `Published`, `Once` and blocking waits.
- [07 Disconnected channels](../spec/07-concurrency/synchronization.md#disconnected-channels): when a channel is disconnected, and what `receive`, `tryReceive` and `send` do then.
- [07 Panics in producers and consumers](../spec/07-concurrency/synchronization.md#panics-in-producers-and-consumers): what a panic on either side disconnects, and why each end is owned inside a `ThreadScope`.
- [07 The `Synchronized` contract](../spec/07-concurrency/synchronization.md#the-synchronized-contract): what a type of your own must uphold to declare it.
- [07 Global state](../spec/07-concurrency/global-state.md#global-state): thread-locals, startup, thread teardown and shutdown.
- [07 Task functions](../spec/07-concurrency/tasks.md#task-functions-explicitly-stepped-coroutines): awaitables, wakers, and `TaskSet`.
- [05 Closure kinds](../spec/05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds) and [unscoped closures](../spec/05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref): what decides a closure's kind, and capture lists.
- [Hard cases](../validation/hard-cases/concurrency-and-memory.md#c-concurrency): concurrency patterns the design must accept, such as nested parallelism and errors in lent work.
