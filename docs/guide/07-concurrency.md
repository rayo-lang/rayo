# 7 · Concurrency

Each frame, ten thousand enemies move, and the game needs their total hp. One core is too slow, so the work spreads over all of them. In C++ the obvious version compiles, and races:

```cpp
float total = 0;
std::for_each(std::execution::par, enemies.begin(), enemies.end(), [&](Enemy& e) {
    e.pos += e.vel * dt;
    total += e.hp;                        // every thread writes 'total'
    enemies[e.target].hp -= e.damage;     // two threads may write one enemy at once
});
```

The compiler says nothing about the race. A frame now and then loses some damage, or a count comes out wrong. In Rayo the same work reads like this:

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

`parallelReduce` merges the results: each job sums its own slice from `0`, and `+` combines the partial sums. Writing `total` from the loop's body, as the C++ does, doesn't compile. This chapter shows why, and the rules turn out to be the ones from [Borrowing](03-borrowing.md), carried across threads.

## Lending work to other threads

**A job system's call borrows its arguments until it returns, as every call does** ([07](../spec/07-concurrency.md#lending-work-to-other-threads)). Closures that borrow the caller's data and run on the library's threads are **lent work**. The library finishes them before the borrows they carry end, which for `join` is when it returns. So the law of exclusivity covers those threads with no new rule:

```swift
join({ integrate(&world.enemies, dt: dt) },             // may run both closures at once, and returns when both are done
     { mix(&world.audio) })                             // fine: each closure writes a different field

join({ integrate(&world.enemies, dt: dt) },
     { drawRadar(world.enemies) })                      // error: one closure reads 'world.enemies' while the other writes it
```

A closure literal borrows what it captures for as long as the call has it. So two closures of one `join` are checked as two arguments are, and the second `join` fails as `f(&x, x)` does. A closure captures the places its body names, such as `world.audio`, not all of `world`, which is why the first one compiles.

**A closure's kind says how the library may call it** ([05](../spec/05-protocols-generics-and-closures.md#closure-kinds)). The compiler infers the kind from the body:

- a non-`mutating` closure only reads its captures, so any number of threads may run it at once, as `forEachInParallel` does;
- a `mutating` closure writes a capture, so only one thread at a time runs it, and each of `join`'s closures may be one;
- a `consuming` closure moves out of a capture, so it runs at most once.

That is what rejects the C++ version's `total`:

```swift
var total: Float = 0
enemies.forEachInParallel { e in
    total += e.hp       // error: writes 'total', so the closure is 'mutating', but the loop runs it on many threads at once
}
```

The body may change `e`, since each call gets its own element. It can't write anything it captures. To merge results from many threads, use a reduction, as `totalHp` does, or an atomic ([below](#atomics)). Work that changes other enemies, such as damage to a target, goes after the call returns, when nothing borrows `enemies` any more.

**Your code needs no `unsafe` for any of this.** The job system's own `unsafe` code promises to call each closure only as its kind allows, and to finish every one before the borrows it carries can end ([07](../spec/07-concurrency.md#the-librarys-promise)).

### Scoped threads

**`Thread.scope` starts threads that may borrow the caller's locals, and returns only when every thread its block spawned has finished** ([07](../spec/07-concurrency.md#scoped-threads)). It works like Rust's `std::thread::scope`:

```swift
Thread.scope { s in
    s.spawn { integrate(&world.enemies, dt: dt) }       // runs on another thread
    mix(&world.audio)                                   // runs on this thread meanwhile
    print(world.enemies.count)                          // error: 's' borrows 'world.enemies' exclusively until the block returns
}                                                       // every spawned thread has finished here
```

`spawn` moves its closure into the scope `s`, and `s` then holds what the closure borrows until the block returns. So the block, or a second `spawn`, that touches `world.enemies` conflicts, as a second argument of one call would.

## What may cross threads: `Sendable`

**Only a value of a `Sendable` type reaches another thread**, moved there or lent there for a call ([07](../spec/07-concurrency.md#what-may-cross-threads-sendable)). The compiler derives this marker protocol from what a type holds, as it derives `Copyable`. It plays the part of Rust's `Send` and `Sync` together.

```swift
struct Enemy(var pos: Vec3, var vel: Vec3 = .zero, var hp: Float = 100)   // Sendable: every field is
struct Hud(var root: WeakPointer<Widget>)               // not Sendable: holds a weak pointer
struct GLTexture(let id: UInt32): ~Sendable             // opts out: the id is valid only on the GL thread
```

- **A struct, enum, tuple or array is `Sendable` when everything it holds is.** std's containers follow their elements, so `List<Enemy>` is `Sendable`, and `List<WeakPointer<Enemy>>` isn't.
- **Object pointers never are.** `UniquePointer`, `WeakPointer` and anything that holds one stay on the object's home thread, since an object's access marks belong to one thread ([Handles and objects](05-handles-and-objects.md)).
- **`Shared<T>` is `Sendable` when `T` is**, and `LocalShared<T>` never is ([06](../spec/06-memory-and-allocators.md#sharedt-data-with-many-owners)).
- **`~Sendable` opts a type out**, as `GLTexture` does: its only field is an integer, but the id means something only on one thread.
- **`unsafe Sendable` promises what the compiler can't check**, as a wrapper over a thread-safe C library's pointer does ([10](../spec/10-errors-and-safety.md#unverified-promises)).

**Lent work captures only `Sendable` values, even by reference.** `forEachInParallel`'s body has the type `@sendable (mutable Enemy) -> Void`, and a `@sendable` function type holds only closures whose captures are all `Sendable`:

```swift
func drawMarkers(_ enemies: mutable List<Enemy>, _ hud: Hud) {
    enemies.forEachInParallel { e in
        mark(hud, at: e.pos)        // error: 'Hud' isn't Sendable, so lent work can't capture it
    }
}
```

Code that uses the HUD runs on the thread that owns it, such as a plain loop after the parallel one.

## Shared mutable state

**Data that several threads share, and change through shared borrows, lives in a `Synchronized` type, which changes only through its own synchronization, such as a lock or atomics** ([07](../spec/07-concurrency.md#atomics-and-locks)). So a shared borrow of one is enough to change it, from any thread. Lent work that changes data through a `mutable` borrow, as `integrate` does, needs none: exclusivity already keeps the threads apart.

### Locks: `Mutex` and `RwLock`

**`Mutex<T>` owns its data, and the only way to reach the data is to lock it**, as with Rust's `Mutex` ([07](../spec/07-concurrency.md#locks-mutex-and-rwlock)). The closure form locks, runs the closure once and unlocks:

```swift
let deaths = Mutex(List<Vec3>())
enemies.forEachInParallel { e in
    if e.hp <= 0 {
        deaths.lock { list in list.append(copy e.pos) }   // fine: one thread at a time holds the list
    }
}
```

The body only calls `lock`, a non-`mutating` method, on `deaths`, so the body stays non-`mutating`, and many threads may run it. The closure that `lock` takes can't keep a view of the list, so nothing reaches the data once the lock is released.

**The guard form returns a guard that holds the lock for as long as it lives:**

```swift
var g = deaths.lock()                    // a MutexGuard<List<Vec3>>
g.value.append(copy boss.pos)
consume g                                // unlocks now; otherwise the end of the scope does
```

- **A guard is scoped.** It can't be stored in a global or an object, returned past the mutex it came from, or held across an `await`.
- **A guard isn't `Sendable`**, so it is released on the thread that took it, as many platform mutexes require ([02](../spec/02-views-and-dependencies.md#lock-guards-are-released-on-the-thread-that-took-them)).
- **Locking a `Mutex` the thread already holds panics**, in either form, so no thread ever gets a second exclusive view of the data:

```swift
deaths.lock { _ in
    deaths.lock { _ in }                 // panics: this thread already holds 'deaths'
}
```

**`RwLock<T>` works like `Mutex`, with `read` for shared access and `write` for exclusive access**, each in both forms:

```swift
let nav = RwLock(NavGrid())
let route = nav.read { grid in findPath(grid, from: start, to: goal) }   // many readers at once
nav.write { grid in grid.block(cellOf(crate.pos)) }                       // one writer, and no readers meanwhile
```

Taking the write lock on a thread that holds either lock panics, and so does taking either lock on a thread that holds the write lock.

### Atomics

**`Atomic<T>` holds a copyable value of 1, 2, 4 or 8 bytes, such as an integer, a `Bool`, a float or a handle, and every operation on it names its memory ordering.** The value must be **padding-free**, with no padding bytes in its layout, since a compare-and-swap compares every byte ([07](../spec/07-concurrency.md#atomics-and-locks)):

```swift
let spawned = Atomic(0)
spawned.add(1, .relaxed)                 // lock-free, through a shared borrow, from any thread
```

The orderings are C++20's: `.relaxed`, `.acquire`, `.release`, `.acqRel` and `.seqCst`. An ordering is a compile-time argument, so one that an operation doesn't accept, such as `.release` on a load, is a compile error.

**`AtomicArray<T>` is a fixed-size array of atomics**, so many threads can add into one grid at once:

```swift
func countCrowds(_ enemies: mutable List<Enemy>, into cells: AtomicArray<Int>) {
    enemies.forEachInParallel { e in
        cells.add(cellOf(e.pos), 1, .relaxed)     // fine: an atomic add, through a shared borrow of 'cells'
    }
}
```

### The `Synchronized` contract

**`Mutex`, `RwLock`, the atomics and std's queues share one contract, the marker protocol `Synchronized`** ([07](../spec/07-concurrency.md#the-synchronized-contract)). A `Synchronized` type's non-`mutating` methods change it only through its own synchronization, and lend its data only under a lock or once nothing writes it again. It is move-only, so every thread synchronizes on the same memory, and it is always `Sendable`. A struct whose fields are all `Synchronized` is `Synchronized` too. A type of your own, such as a lock-free queue, declares it with `unsafe Synchronized`, since the compiler can't check the implementation.

## Threads that outlive the caller

**A thread may run after the function that started it returns, so its body borrows nothing: it owns its captures, and lists them** ([07](../spec/07-concurrency.md#what-a-thread-can-share)):

```swift
var level = loadLevel()
let bounces = 3
Thread.start(name: "bake") {
    bakeLighting(level, bounces: bounces)                    // error: unlisted captures; a thread body can't borrow them
}
Thread.start(name: "bake") { [move level, copy bounces] in   // fine: the thread owns 'level', and a copy of 'bounces'
    bakeLighting(level, bounces: bounces)
}
```

A thread's body is an **unscoped** closure, which owns its captures ([05](../spec/05-protocols-generics-and-closures.md#unscoped-closures-closuref)). `[move level]` moves the level in, so this function can't use it afterwards. `[copy bounces]` copies a copyable value and leaves it usable here. Every capture must be `Sendable`.

**Data that many threads hold lives behind a `Shared`, whose value is `Frozen` or `Synchronized`** ([03](../spec/03-handles-and-objects.md#sharing-across-threads)). A weak link to it is copyable, and `Sendable` when the value is:

```swift
let mixer = Shared(Mutex(AudioMixer()))
let m = mixer.weak()                                         // a WeakShared<Mutex<AudioMixer>>
Thread.start { [copy m, copy clip] in
    if let mx = m.upgrade() { mx.value.lock { $0.play(clip) } }   // one more owner while 'mx' lives
}
```

**Threads, locks and job systems are library code, not language features** ([07](../spec/07-concurrency.md)). The runtime's one primitive for starting a thread is `Runtime.startThread`, and a job system of your own can start its workers with it ([07](../spec/07-concurrency.md#starting-a-thread-runtimestartthread)).

### Queues and channels

**A `Channel` hands items from one thread to another through two owned ends** ([07](../spec/07-concurrency.md#queues-and-channels)):

```swift
func startRenderer() -> (Thread, Sender<Shared<Snapshot>>) {
    let (tx, rx) = Channel<Shared<Snapshot>>.make(capacity: 3)
    let render = Thread.loop(name: "render", receiving: rx) { snap in   // 'rx' moves in; one call per snapshot
        draw(snap)
    }
    return (render, tx)                                       // the simulation keeps the sender
}
```

- **The ends are move-only.** `Sender<T>` and `Receiver<T>` are `Sendable` when `T` is, so each end can move to the thread that uses it.
- **Exclusivity makes the one `Receiver` the single consumer.** Its `pop()` and `waitPop()` are `mutating`, so the compiler checks that one thread at a time consumes, at no run-time cost. The sender's `push(_:)` is `mutating` too, so each `Sender` is one producer at a time.
- **std's queues, such as `MpscQueue` and `SpscQueue`, are `Synchronized`**, so a global `let` of one serves any thread. `pop()` returns `nil` at once when the queue is empty, and `waitPop()` parks the thread until an item comes. A queue with a single producer or consumer checks that side at run time.

## Global state

**Safe code has no unsynchronized mutable globals**, since every thread can reach a global ([07](../spec/07-concurrency.md#global-state)):

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

- **A global `let` that safe code uses has a `Sendable` type.** Every thread reads it through shared borrows, with no access checks. It changes only through its own synchronization: a `Synchronized` value it holds, as `config` and `spawned` do, or a `Shared`'s count.
- **A `@threadlocal var` gives each thread its own copy.** Each access takes a run-time mark, since the compiler can't see a callee touching it, so a conflicting access panics as an object's does.
- **A bare global `var` can be accessed only in `unsafe` code**, which answers for which threads touch it ([C and compile time](08-c-and-compile-time.md)). The fix is one of the two forms above: `let frames = Atomic(0)`, or a `@threadlocal var` when each thread counts its own.

**Globals are initialized before `main`, one module at a time, in source order, on one thread** ([07](../spec/07-concurrency.md#initialization-at-startup)). Reading a global before it is initialized is a compile error where the compiler can see it, and a panic where it can't. A `@threadlocal var` is the exception: each thread initializes its own copy, on that thread, before it runs any other code.

## Stepped tasks

**A `task func` can suspend at `await`, and continues when its owner steps it** ([07](../spec/07-concurrency.md#task-functions-explicitly-stepped-coroutines)). It suits a script that spans frames, and it never runs on its own:

```swift
task func openDoor(_ door: owned Handle<Door>) with (game: mutable Game) {
    guard let d = game.doors[door] else { return }
    game.audio.play(d.creakSound, at: d.pos)
    await seconds(0.5)                                     // suspends here; a later step resumes
    game.audio.play(d.slamSound, at: d.pos)                // error: 'd' borrows 'game.doors' across an 'await'
    game.doors[door]?.state = .open                        // fine: looks the door up again
}

var scripts = TaskSet<Game>(capacity: 512)
scripts.start(openDoor(frontDoor))                         // calling openDoor runs nothing: it returns the task
scripts.step(&game)                                        // resumes pending and woken tasks once each
```

- **A task is a value** whose size the compiler knows, so it never allocates on its own. Its parameters are `owned`, and the locals it keeps across an `await` live inside it.
- **No borrow lives across an `await`**, since between steps the task holds only what it owns. So `d` must end before the `await`: using it after is the error above, and the code there looks the door up again ([07](../spec/07-concurrency.md#semantics)).
- **The resume parameter, `game` here, is lent anew at every step**, so the task never holds it in between.

A `TaskSet` isn't `Sendable`, so it and its tasks stay on one thread.

## In the spec

- [07 Concurrency](../spec/07-concurrency.md#why-safe-code-cant-race): the four ways two threads can reach the same memory, and why safe code can't race.
- [07 The library's promise](../spec/07-concurrency.md#the-librarys-promise): what a job system's `unsafe` code promises, and thread-locals in lent work.
- [07 Sendable](../spec/07-concurrency.md#what-may-cross-threads-sendable): every rule that derives `Sendable`, and where it is required.
- [07 Atomics and locks](../spec/07-concurrency.md#atomics-and-locks): memory orderings, `Mutex` and `RwLock`, queues, channels, `Published`, `Once` and blocking waits.
- [07 The `Synchronized` contract](../spec/07-concurrency.md#the-synchronized-contract): what a type of your own must uphold to declare it.
- [07 Global state](../spec/07-concurrency.md#global-state): thread-locals, startup, thread teardown and shutdown.
- [07 Task functions](../spec/07-concurrency.md#task-functions-explicitly-stepped-coroutines): awaitables, wakers, and `TaskSet`.
- [05 Closure kinds](../spec/05-protocols-generics-and-closures.md#closure-kinds) and [unscoped closures](../spec/05-protocols-generics-and-closures.md#unscoped-closures-closuref): what decides a closure's kind, and capture lists.
- [Hard cases](../spec/hard-cases.md#c-concurrency): concurrency patterns the design must accept, such as nested parallelism and errors in lent work.
