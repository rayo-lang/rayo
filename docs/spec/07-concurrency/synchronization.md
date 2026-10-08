# Atomics and synchronization

[07 · Concurrency](../07-concurrency.md)

## Atomics and locks

**std's atomics, locks, queues, snapshots, one-time values and blocking primitives implement the `Synchronized` contract** ([below](#the-synchronized-contract)). So they may be shared across threads, and change through a shared borrow, as a global `let` of one does ([Global state](global-state.md#global-state)).

**`Atomic<T>` holds a copyable, padding-free value of 1, 2, 4 or 8 bytes**, such as an integer, `Bool`, float, pointer or `Handle<T>`. It must be padding-free since a compare-and-swap compares every byte ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). Each operation takes an explicit ordering, as in `counter.add(1, .relaxed)`, and is lock-free: none blocks or waits for another thread.

**Rayo uses the C++20 memory model.** The orderings `.relaxed`, `.acquire`, `.release`, `.acqRel` and `.seqCst` mean what they mean there. So does a data race, which safe code can't write ([Why safe code can't race](race-freedom-and-sendable.md#why-safe-code-cant-race)).

**An ordering is a `const` argument, and one the operation doesn't accept is a compile error:**

- a load takes `.relaxed`, `.acquire` or `.seqCst`;
- a store takes `.relaxed`, `.release` or `.seqCst`;
- a read-modify-write takes any of the five;
- a compare-and-swap's failure ordering is `.relaxed`, `.acquire` or `.seqCst`.

**`AtomicArray<T>` is a fixed-size array of atomics.**

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

**Each form lends the data only while the lock is held:**

- **The closure form calls the closure exactly once**, so it takes the most general closure kind, `consuming`, and the closure may move a captured local out, as the first one moves `m`. The closure's parameter isn't `keep`, so no view of the protected data outlives the lock ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)).
- **The guard form returns an exclusive guard from a shared `self`.** A mutable view normally needs an exclusive input, and a guard is one exception, since its `Synchronized` type enforces its exclusivity at run time ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#mutable-views)). A guard is scoped, so it can't be:
    - stored anywhere unscoped, such as a global, a `StablePool` or an object;
    - returned past the mutex it came from;
    - held across an `await`.

**Relocking a `Mutex` that the same thread already holds panics**, in either form. That includes relocking from lent work that the lending thread runs while an outer frame of it holds the lock. So no thread ever gets a second exclusive view.

**Guards have `@guard` types**, so a guard is released only on the thread that took it, as many platform mutexes require ([02](../02-views-and-dependencies/dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)), and points only into the lock it came from ([below](#the-synchronized-contract)).

**`RwLock<T>` works like `Mutex`, with `read` (shared) and `write` (exclusive) in both forms.** Taking the write lock on a thread that holds either lock, or either lock on a thread that holds the write lock, panics, as relocking a `Mutex` does. A read lock taken again on a thread that holds one is granted at once, even while a writer waits, since that writer can't proceed before the outer read ends.

### Queues and channels

**Queues and channels pass owned items from producers to consumers.**

**Queues have `pop()`, which returns a `T?` and doesn't block, and `waitPop()`, which returns a `T` and does.**

**Single-producer and single-consumer queues check their single sides at run time.** Overlapping calls on one side panic. Each call's check synchronizes with the previous call on that side, whichever thread made it. So the algorithm never sees two producers or two consumers at once, and sees successive ones in order.

**`Channel<T>` makes a queue that two owned ends share, a `Sender<T>` and a `Receiver<T>`:**

```swift
let (tx, rx) = Channel<Request>.make(capacity: 64)   // tx: a Sender<Request>, rx: a Receiver<Request>
```

The ends are move-only, unscoped values that point to shared heap state, so `T` must be `~Scoped` ([02](../02-views-and-dependencies/scoped-values.md#generic-code-and-scoped)).

**The ends aren't `Synchronized`.** `rx.pop()` and `rx.waitPop()` are `mutating`, so exclusivity makes the one `Receiver` the single consumer statically. `tx.push(_:)` is `mutating` too, so each `Sender` is one producer at a time.

**The shared state counts the ends that own it.** A sender queued inside its own channel is a cycle that dropping the `Receiver` breaks, since that destroys the queued items. Other cycles, such as a `Receiver` queued inside its own channel, leak.

### Snapshots, one-time values and waits

**These `Synchronized` types publish a value for any thread to read, hold a value set once, or make a thread wait:**

- **`Published<T: Frozen & Sendable>`** holds a value that any thread reads and replaces. `p.snapshot()` returns a new owner of the current value, a `Shared<T>`, adding one to its count without waiting. `p.publish(v)` swaps in a new value and drops its own owner of the old one, which whoever drops the last owner destroys ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)), so a snapshot taken before the swap stays valid.
- **`Once<T>`** is set once. Its `get()` lends a read-only `Borrow<T>?`, `nil` until the value is set.
- **Blocking primitives** are `Event`, `Condvar`, `Semaphore` and `Future`, whose waits park the thread ([below](#parking-and-waking-a-thread)).

**A `Condvar` wait consumes the guard and returns a new one:**

```swift
g = cv.wait(consume g)       // unlocks, parks, relocks after it wakes, and returns a new guard
```

`g` can be consumed only after the last use of every view derived from it, so no view of the protected data survives the unlock. The mutex is in the consumed guard's dependency set, so the wait borrows both the condvar and the mutex.

### The `Synchronized` contract

**A `Synchronized` type's non-`mutating` methods mutate only through the type's own synchronization.** The language defines this contract, which the types above share, as the marker protocol **`Synchronized`**. That property is what makes such a value safe to share across threads as a shared borrow, whether lent or held in a global `let` ([Global state](global-state.md#global-state)).

**A `Synchronized` value's memory is the one copy that every thread synchronizes on, and safe code never reads what its synchronization writes with a plain load.** For that, its type:

- **is move-only** (the conformance implies `~Copyable`), so every thread synchronizes on the same memory;
- **holds no niche** ([04](../04-types/enums.md#optionals)), since other threads write its bytes, while reading an optional's tag is a plain load;
- **keeps what its synchronization writes out of safe code's reach.** Every stored field that its non-`mutating` methods write is `unsafe` or itself `Synchronized`. So no safe access reads it with a plain load: not by name, reflection, `SoA` column, protocol witness, or derived `==` or `hash(into:)` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#conformances), [09](../09-compile-time/reflection.md#reflection-and-access-control)). For the same reason it is never `Frozen` or `Pod` ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability), [04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)).

**A `Synchronized` type hands values to other threads, and lends views of its data, only in ways that keep them race-free and exclusive.** For that, it:

- **has unscoped contents that are `Sendable` or raw pointers**, which it hands to other threads, and which absorption can't follow through a shared `self` ([02](../02-views-and-dependencies/scoped-values.md#generic-code-and-scoped)). So `Mutex<Span<T>>` and `Mutex<WeakPointer<T>>` are compile errors, and `Mutex<List<T>>` is fine when `T` is `Sendable`. So the type is itself `Sendable`. A raw pointer handed over this way, as by `Atomic<*T>` or an allocator's `Allocation`, is used only in `unsafe` code, which answers for what it points at ([10](../10-errors-and-safety/unsafe-code.md#what-unsafe-code-upholds));
- **takes elements in and hands them out as owned values**, each handed out after, in happens-before order, the call that took it in, and lends views of them only as the next bullets allow;
- **grants a view only while no conflicting view of the same data is live, on any thread**: an exclusive guard or closure argument while no other view is live, and a shared one while no exclusive one is. Each view it grants happens after the end of every conflicting view it granted before. A request that would conflict with a view its own thread holds panics or blocks, and never succeeds, so a re-entrant lock can't satisfy the contract;
- **declares every guard it returns from a shared `self` `@guard`, and each guard points only into its lock**: the lock's own storage, or `.system` heap state that the lock points to and keeps allocated while the guard lives. So each guard is released on the thread that took it ([02](../02-views-and-dependencies/dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them));
- **lends a view of its interior only in one of two ways:**
    - under a lock, through a closure it runs or a `@guard` guard it returns, as `Mutex` and `RwLock` do;
    - as a read-only view of data that its non-`mutating` methods never write again, except through that data's own synchronization, and never free before the value itself is destroyed, as `Once.get()` lends.

**A `Synchronized` type is bitwise-movable whenever nothing borrows it.** The language moves a value only when nothing borrows it. An `unsafe Synchronized` conformance promises that the unborrowed value keeps no pointer to itself and has no address registered anywhere. Moving or destroying it stays sound even when a guard it returned is never destroyed ([10](../10-errors-and-safety/unsafe-code.md#aliasing-and-skipped-deinits)), as when the guard sits in a stale container. Its lock then stays held.

**`Synchronized` is derived, with no promise, for these types, whose non-`mutating` methods can change them only through their `Synchronized` parts:**

- an inline array whose element type is `Synchronized`;
- a struct or tuple with at least one stored field that is `Synchronized` or a `Shared` of a `Synchronized` value, and every other stored field one of those, or `Frozen`, `Sendable` and unscoped.

Those methods change a `Shared` field's value only through that value's own synchronization. So such a struct can be a `Shared`'s value ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)):

```swift
struct Services(                                   // Synchronized, derived
    let log: Mutex<List<Message>>,
    let registry: Mutex<Registry>,
    let config: Published<GameConfig>,
    let mixer: Shared<Mutex<AudioMixer>>
)
let services = Shared(Services(log: Mutex(…), registry: Mutex(…), config: Published(…), mixer: Shared(Mutex(AudioMixer()))))   // fine: a Shared of it
```

**Declaring a conformance to `Synchronized` requires `unsafe`**, because the compiler can't verify the implementation ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)):

```swift
struct SpinQueue<T>(…): unsafe Synchronized { … }   // in the type's declaration
extension SpinQueue: unsafe Synchronized {}          // or, instead, in an extension
```

### Parking and waking a thread

**A blocking primitive parks its waiting thread through the runtime**, which any `unsafe` code may call:

```swift
unsafe static func park(on word: *UInt32, expected: UInt32, timeout: Int?) -> Bool { … }   // Runtime's: parks the calling thread on 'word'
unsafe static func wake(on word: *UInt32, count: Int) { … }                                 // Runtime's: wakes threads parked on 'word'
```

**`park` parks the calling thread on `word` if it still holds `expected`**, until another thread wakes it or `timeout` nanoseconds pass. It returns `false` only when the timeout passed. It may also return early, so its caller checks its condition again. Its caller promises that `word` stays live and is accessed only atomically meanwhile.

**`wake` wakes up to `count` threads parked on `word`.**

**A parked thread keeps everything it holds**, so its live borrows still count as uses of their allocators ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).
