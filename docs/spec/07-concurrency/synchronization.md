# Atomics and synchronization

[07 · Concurrency](../07-concurrency.md)

Some values must be shared even while their state changes. Atomics, locks and queues make those changes safe by coordinating access among threads. Rayo treats them as library types with a synchronization contract, rather than giving each one a separate language rule.

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

**Creation happens before use.** Creating a `Shared` value, and registering an allocator, each happen before every use through a value that names what it made. That holds however the value was passed on, by stores whose value came from loads, `.relaxed` atomics included. Each creation ends with a release fence before it hands the value out, so its writes count for every store of the value it makes, by 11's "Released" condition. The "Carried" condition then takes them along any chain of such stores ([11](../11-compilation-model.md#what-a-target-must-provide)). So the check each use makes, which loads through the value, reads what the creation wrote, and the use is ordered after the creation.

**Each creation is entered, after its own writes, in a shared table that behaves as a linearizable map.** Three tables are shared this way:

- the interner's entry table, keyed by text ([04](../04-types/collections.md#collections-and-strings));
- the weak-link slots that `WeakShared(bits:)` and upgrades resolve through ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners));
- the allocator registry, which an `Allocator` id resolves through ([06](../06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator)).

**Each table keeps this contract:**

- **One order.** Every insert, lookup and removal takes effect atomically at one point, in a single total order consistent with happens-before. A resize changes no entry: a lookup during a resize returns what it would if no resize ran.
- **Synchronization.** Each lookup or check that finds an entry synchronizes with some release that the entry's insert happens before. Under a lock that release is the unlock, and after a lock-free migration it is the migration's release of the copy.
- **One entry per text.** The interner holds at most one entry per text. An insert of a text that is already present fails and returns the existing entry, which the inserting thread then holds as though it had looked it up.
- **Exclusive keys.** In the weak-link slots and the allocator registry, a creation's key is its slot together with that slot's generation, or its allocator word, and no other creation in the run ever holds it. So a reused slot never matches old bits.

**How a table keeps the contract is the implementation's choice**: a lock, lock-free compare-and-swap, or any mix of them that keeps it.

**A creation's writes count for every store that a thread makes after finding its entry**, by 11's "Synchronized" condition, since they happen before the insert, which happens before a release that the finding synchronizes with ([11](../11-compilation-model.md#what-a-target-must-provide)).

**A check that resolves bits finds the entry or none, never stale contents.** A value rebuilt with no carried chain, such as a `WeakShared(bits:)` made from integers that control flow rebuilt or that passed through C, then finds one of two things. Either it finds the entry, whose contents it reads safely since the insert happens before a release it synchronizes with, or it finds none.

**Such a value may find no entry for a creation that is still live**, since nothing orders the creation before the check. Then `WeakShared(bits:)` and `Shared.adopt` read `nil`, and opening a value through the allocator panics as it does for an unregistered allocator word ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)). Each outcome is safe and defined.

**Interning a text happens before every read of that `Name`'s text or of its stored hash**, however the `Name` was passed on, by stores whose value came from loads. Interning a new entry writes its text and hash, then a plain word, written once with a release store. Every read of the text or the hash first loads that word with an acquire load.

**Interning inserts the entry into the interner's table after the word's store**, then ends with a release fence before it hands the `Name` out. When the text is already present, the insert fails and returns the existing entry, so a text never gets two `Name`s. The thread then returns that entry, as a lookup that finds it does, and never hands out its own.

**That acquire load reads the word's release store, however the `Name` was passed on**, through a `.relaxed` atomic or a third thread included ([11](../11-compilation-model.md#what-a-target-must-provide)):

- **A new entry.** The word's release store comes first, then the insert, then the fence, which puts the word's store before every store of the `Name` that the interning thread makes. So the word's store counts for each by 11's "Released" condition. The "Carried" condition then takes it along any chain of threads that passes the `Name` on.
- **An existing entry.** A lookup, or a failed insert, that finds the entry synchronizes with a release that the insert happens before, and the word's store happens before that insert. So the word's store counts for every store of the `Name` that the finding thread makes, by "Synchronized", and "Carried" takes it on as for a new entry.

So by 11's rule the acquire load, which goes through the `Name`, reads a value no older than the word's store. The word is written once and entries are never freed, so it reads that store. An acquire load that reads a release store synchronizes with it. So the text's bytes and its hash are visible, and reading them races with nothing.

**The fence costs little.** On x86 it is only a compiler barrier, and on ARMv8 and Power one barrier instruction per creation, set against the allocation or the interning step it ends.

**A literal's entry has the word already set in its frozen data**, in read-only data before the program starts ([04](../04-types/collections.md#interned-literals)). Hashing reads the stored hash, so the rule above orders it. `==` reads no entry, so it promises nothing beyond the value it compares ([04](../04-types/collections.md#collections-and-strings)).

### Locks: `Mutex` and `RwLock`

**`Mutex<T>` owns its data, and reaching it requires locking**, in closure form or as a guard:

```swift
let log = Mutex(List<Message>())
log.lock { msgs in msgs.append(m) }      // closure form: lock takes 'consuming (mutable T) -> R', called once

var g = log.lock()                       // guard form: an owned, move-only, scoped MutexGuard<List<Message>>
g.value.append(n)                        // views of g.value depend on g
_ = g                                    // unlocks; otherwise its deinit unlocks at scope end

log.lock { msgs in
    log.lock { _ in }                    // panics: this thread already holds 'log'
}
```

**Each form lends the data only while the lock is held:**

- **The closure form calls the closure exactly once**, so it takes the most general closure kind, `consuming`, and the closure may move a captured local out, as the first one moves `m`. The closure's parameter isn't `keep`, so no view of the protected data outlives the lock ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)).
- **The guard form returns an exclusive guard from a shared `self`.** A mutable view normally needs an exclusive input, and a guard is one exception, since its `Synchronized` type enforces its exclusivity at run time ([02](../02-views-and-dependencies/dependency-projection-and-results.md#mutable-views)). A guard is scoped, so it can't be:
    - stored anywhere unscoped, such as a global, a `StablePool` or an object;
    - returned past the mutex it came from;
    - held across an `await`.

**Relocking a `Mutex` that the same thread already holds panics**, in either form. That includes relocking from lent work that the lending thread runs while an outer frame of it holds the lock. So no thread ever gets a second exclusive view.

**Guards have `@guard` types**, so a guard is released only on the thread that took it, as many platform mutexes require ([02](../02-views-and-dependencies/dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)), and points only into the lock it came from ([below](#the-synchronized-contract)).

**`RwLock<T>` works like `Mutex`, with `read` (shared) and `write` (exclusive) in both forms.** Taking the write lock on a thread that holds either lock, or either lock on a thread that holds the write lock, panics, as relocking a `Mutex` does. A read lock taken again on a thread that holds one is granted at once, even while a writer waits, since that writer can't proceed before the outer read ends.

**A panic that unwinds out of a lock's exclusive access poisons the lock.** That is a `Mutex`'s access, or an `RwLock`'s `write` access, through a guard or the closure form. An `RwLock`'s `read` access never poisons, since it changes nothing. The unwind still releases the lock, as it destroys the guard or ends the closure form's call, so a panic never leaves a lock held.

**While a lock is poisoned, `lock`, `read` and `write` on it panic, until `clearPoison()` resets it:**

```swift
func clearPoison()            // Mutex's and RwLock's: a shared borrow, so any thread may call it
```

The panic left the data as it found it, perhaps half-changed. Only the panicking thread's `recover` closure sees that panic and can repair the data ([10](../10-errors-and-safety/panics.md#catching-a-panic-catchpanic)). So another thread, which never sees it, can't take the half-changed data for a whole value.

### Queues and channels

**Queues and channels pass owned items from producers to consumers.** A queue is one `Synchronized` value that its producers and consumers all borrow. A channel is a queue that owned ends share, so it can tell its consumer when every producer is gone ([below](#disconnected-channels)).

**Queues have `pop()`, which returns a `T?` and doesn't block, and `waitPop()`, which returns a `T` and does.**

**Single-producer and single-consumer queues check their single sides at run time.** Overlapping calls on one side panic. Each call's check synchronizes with the previous call on that side, whichever thread made it. So the algorithm never sees two producers or two consumers at once, and sees successive ones in order.

**A queue has no close, since no code owns a side of it.** Its producers and consumers borrow it, often as a global `let` that lives until shutdown, so nothing marks the last producer gone. `waitPop()` parks until another item comes, for ever if none does. A consumer that must learn when its producers are done takes its items from a channel instead.

**`Channel<T>` makes a channel, a queue that two kinds of owned ends share, `Sender<T>` and `Receiver<T>`:**

```swift
let (tx, rx) = Channel<Request>.make(capacity: 64)   // tx: a Sender<Request>, rx: a Receiver<Request>
```

The ends are move-only, unscoped values that point to shared heap state, so `T` must be `~Scoped` ([02](../02-views-and-dependencies/scoped-values.md#generic-code-and-scoped)). A channel has one `Receiver`, and as many `Sender`s as `share()` makes. Like `Shared`'s `share()`, it adds an owner of the shared state visibly ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)).

**Each end has its own methods:**

```swift
func share() -> Sender<T>                                        // Sender<T>'s: another Sender of the same channel
mutating func send(_ item: owned T) -> Void!Disconnected<T>      // Sender<T>'s: parks while full; fails once the Receiver is gone
mutating func trySend(_ item: owned T) -> Void!TrySendError<T>   // Sender<T>'s: never parks
mutating func receive() -> T?                                    // Receiver<T>'s: parks while empty; nil once every Sender is gone
mutating func tryReceive() -> T!TryReceiveError                  // Receiver<T>'s: never parks
mutating func receive(timeout: Duration) -> T!ReceiveTimeoutError   // Receiver<T>'s: parks while empty, for at most 'timeout'
```

**A channel holds at most `capacity` items, and `capacity` is at least 1.** `make` panics on a smaller one, such as `make(capacity: 0)`: a channel with no room could never take an item, so every `send` would park for ever ([10](../10-errors-and-safety/panics.md#what-panics)).

**`send` parks while the channel is full and connected**, and goes on once the `Receiver` takes an item and makes room. So a producer that runs ahead of its consumer waits for it, rather than filling memory with items nobody has taken.

**The ends aren't `Synchronized`.** `receive()`, `receive(timeout:)` and `tryReceive()` are `mutating`, so exclusivity makes the one `Receiver` the single consumer statically. `send(_:)` and `trySend(_:)` are `mutating` too, so each `Sender` is one producer at a time.

**The shared state counts the ends that own it**, which also tells each side when the other is gone ([below](#disconnected-channels)). A sender queued inside its own channel is a cycle that dropping the `Receiver` breaks, since that destroys the queued items. Other cycles, such as a `Receiver` queued inside its own channel, leak.

### Disconnected channels

**A channel is disconnected once the ends on one side are all gone, so the other side never waits for an end that can't act.** Each direction has its own condition:

- **For receiving.** A channel is disconnected for receiving once every `Sender` is gone and no item is left in it. The items sent before then are still received, each `Sender`'s items in the order it sent them.
- **For sending.** A channel is disconnected for sending once the `Receiver` is gone.

**An end is gone once it is destroyed, however that happens**: dropped with `_ =`, at the end of its scope, or by an unwind ([10](../10-errors-and-safety/panics.md#unwinding)).

**The end whose destruction disconnects the channel wakes every thread parked on it** ([below](#parking-and-waking-a-thread)), so none waits for an end that is gone:

- **The last `Sender`** wakes the thread parked in `receive()` or `receive(timeout:)` on the empty channel. That `receive()` returns `nil`, and that `receive(timeout:)` fails with `.disconnected`.
- **The `Receiver`** wakes every thread parked in `send` on the full channel. Each of those sends fails, and hands its item back in `Disconnected<T>`.

**Destroying the `Receiver` runs in this order:**

1. It disconnects the channel for sending, and wakes every thread parked in `send`.
2. It destroys the items left in the channel, on the destroying thread, oldest first. When one item's `deinit` panics, the rest are still destroyed, as an unwind destroys the rest of any value whose destruction panicked ([10](../10-errors-and-safety/panics.md#unwinding)).

So each send either put its item in before the disconnection, and the item is destroyed with the `Receiver`, or fails, and hands the item back.

**A channel orders the threads that use its ends, so what one thread did before is visible to the other:**

- each send happens before the receive that returns its item;
- destroying each `Sender` happens before every `receive()` that returns `nil`, and every `tryReceive()` or `receive(timeout:)` that fails with `.disconnected`;
- destroying the `Receiver` happens before each `send` that fails, and each `trySend` that fails with `.disconnected`.

**`receive()` parks while the channel is empty and connected, and returns `nil` once it is disconnected for receiving.** So a consumer's loop ends when its producers are done, after it has handled every item they sent:

```swift
while let r = rx.receive() { handle(r) }      // ends once every Sender is gone and the channel is empty
for r in &rx { handle(r) }                    // the same loop
```

**A `Receiver` is a `MutableSequence` whose iterator calls `receive()`**, so `for r in &rx` hands each item over, and ends at disconnection ([04](../04-types/collections.md#iteration)). The loop holds `rx` exclusively, as each `receive()` does, and the `&` says so.

**`tryReceive()` never parks, and tells an empty channel from a disconnected one:**

```swift
enum TryReceiveError: Error {
    case empty              // connected, with no item yet
    case disconnected       // every Sender is gone, and no item is left
}
```

**`receive(timeout:)` parks as `receive()` does, until `timeout` has passed on `MonotonicClock`, and tells a timeout from a disconnection** ([Time](#time-duration-and-instant)):

```swift
enum ReceiveTimeoutError: Error {
    case timedOut           // connected, and no item came before the timeout passed
    case disconnected       // every Sender is gone, and no item is left
}
```

It fails with `.timedOut` no sooner than `timeout` after the call, as `Thread.sleep(for:)` parks for at least its `Duration`. An item that is there already comes back at once, so a `timeout` of zero or less acts as `tryReceive()` does. A consumer that must notice producers that have stalled, such as a watchdog, waits this way instead of parking for ever.

**`send` fails once the channel is disconnected for sending, and an item a send can't deliver comes back to its sender:**

```swift
struct Disconnected<T>(let item: T): Error      // the error of send, and of a future's fulfill: the value nobody will take
```

**`trySend` never parks, and hands the item back whether the channel is full or disconnected:**

```swift
enum TrySendError<T>: Error {
    case full(T)            // connected, with no room
    case disconnected(T)    // the Receiver is gone
}
```

**A send's result is a `Result`, so the unused-value rule makes the sender check it or drop it on purpose** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values)):

```swift
tx.send(r)                // error: the Void!Disconnected<Request> is never used
_ = tx.send(r)            // fine: if the Receiver is gone, the request is destroyed here
try tx.send(r)            // fine in a function that fails with Disconnected<Request>
```

### Futures

**A future carries one value from a producer to a waiter, through two owned ends that `Future<T>.make()` returns:** a `Promise<T>`, which the producer fulfills once, and a `Future<T>`, which the waiter waits on.

```swift
let (promise, lightmap) = Future<Lightmap>.make()                // promise: a Promise<Lightmap>, lightmap: a Future<Lightmap>
_ = Thread.start(name: "bake") { [move promise, move level] in   // '_ =' detaches the thread
    _ = promise.fulfill(bakeLightmap(level))                     // '_ =': if nobody waits any more, the lightmap is destroyed
}
if let map = lightmap.wait() { apply(map) }                      // parks until the bake is done; nil if its Promise went unfulfilled
```

**The ends are move-only, unscoped values that point to shared heap state, so `T` must be `~Scoped`.** Each is `Sendable` when `T` is, so the producer's thread can own the `Promise`. Neither is `Synchronized`: each has one owner, and fulfilling or waiting consumes the end, so a future has one producer and one waiter.

**Each end is used once:**

```swift
consuming func fulfill(_ value: owned T) -> Void!Disconnected<T>   // Promise<T>'s: fails, handing the value back, once the Future is gone
consuming func wait() -> T?                                        // Future<T>'s: parks until fulfilled; nil once disconnected
```

`fulfill` consumes the `Promise`, so a future gets at most one value, and wakes whatever waits on the `Future`: the thread parked in its `wait()`, or the task awaiting it. `wait()` consumes the `Future`, and so does `await` in a task, where a `Future<T>` is an awaitable whose `Output` is `T?` ([Awaitables in std](tasks.md#awaitables-in-std)). A value that is fulfilled but never taken is destroyed with the `Future`, on the thread that destroys it.

**A `Future`'s `isReady` says whether a wait would return at once, and never parks or consumes the `Future`:**

```swift
var isReady: Bool { get }     // Future<T>'s
```

It is `true` once the future is fulfilled or disconnected, and then a `wait()` or an `await` returns at once. A ready future stays ready, so nothing the producer does can make a check that read `true` wrong. Code that must not park, such as a frame loop, checks it each step:

```swift
while !lightmap.isReady { drawLoadingScreen() }   // never parks: checks once a frame
if let map = lightmap.wait() { apply(map) }       // returns at once: the bake is done, or its Promise is gone
```

**A future is disconnected as a channel is, once the end on one side is gone** ([above](#disconnected-channels)):

- **For waiting.** A future is disconnected for waiting once its `Promise` is destroyed unfulfilled: dropped, at the end of its scope, or by an unwind. That destruction wakes whatever waits on the future, which then gets `nil`.
- **For fulfilling.** A future is disconnected for fulfilling once its `Future` is destroyed. `fulfill` then fails, and hands the value back in `Disconnected<T>`, as a `send` does.

**A future orders the threads that use its ends, so what one thread did before is visible to the other:**

- fulfilling the `Promise` happens before the `wait()` or `await` that returns its value, and before `isReady` reads `true`;
- destroying an unfulfilled `Promise` happens before the `wait()` or `await` that gives `nil`, and before `isReady` reads `true`;
- destroying the `Future` happens before a `fulfill` that fails.

**A panic in the producer disconnects the future as it disconnects a channel**, and never reaches the waiter ([below](#panics-in-producers-and-consumers)).

### Panics in producers and consumers

**A panic in a producer disconnects what it produces into, but never reaches the consumer.** The unwind destroys the ends that the panicking code owns, its `Sender`s and its `Promise`s, as it destroys every live value ([10](../10-errors-and-safety/panics.md#unwinding)). When one was a channel's last `Sender`, the consumer's `receive()` returns `nil` once it has taken the items sent before ([Disconnected channels](#disconnected-channels)). A future's waiter gets `nil` ([Futures](#futures)). So a consumer waiting on a producer that panicked wakes, rather than parking for ever as it would on an `Event` that nothing signals.

**The ends carry values, not panics.** The consumer sees the disconnection as it would see producers that finished. The panic itself goes to whoever joins the producer's thread ([Joining a thread](thread-work.md#joining-a-thread)), or to the call that lent the producer its work ([Panics in lent work](thread-work.md#panics-in-lent-work)). The panic of a detached producer, such as the bake thread that fulfills a future ([above](#futures)), reaches only the report, since nothing joins it. So a consumer that must know why its producers stopped joins them.

**A panic in the consumer works the other way round.** The unwind destroys the `Receiver` or the `Future`, and each `send` or `fulfill` after that fails.

**So that no panic leaves a thread waiting, code in a `ThreadScope` owns each channel or future end it uses inside the scope**, in the block or in the spawned closure that uses it ([Scoped threads](thread-work.md#scoped-threads)). The compiler doesn't check this. Owning the ends there is what lets each unwind in the scope destroy the ends its code used:

```swift
ThreadScope.run { s in
    var assets = consume rx                                  // the block owns the Receiver: an unwind out of the block destroys it
    let meshes = tx.share()
    s.spawn { [move meshes] in loadMeshes(into: &meshes) }   // each thread owns its Sender, so its panic destroys it inside the scope
    s.spawn { [move tx] in loadSounds(into: &tx) }           // the last producer takes the original
    for asset in &assets { register(asset) }                 // ends once both producers are done, or have panicked
}
```

**Code that only borrows an end compiles, but the end then outlives everything that happens in the scope**, panics included, since nothing destroys a frame outside the scope until `ThreadScope.run` has joined every thread:

- **A borrowed `Sender`**, such as `&tx`. The channel never disconnects inside the scope, so a consumer there waits for ever, after a producer's panic or even after every producer finishes, and `ThreadScope.run` waits for it.
- **A borrowed `Receiver`**, such as `&rx`. After the consumer's panic, a producer parked in `send` on the full channel is never woken, and `ThreadScope.run` waits for it.

### Snapshots, one-time values and waits

**These `Synchronized` types publish a value for any thread to read, hold a value set once, or make a thread wait:**

- **`Published<T: Frozen & Sendable>`** holds a value that any thread reads and replaces. `p.snapshot()` returns a new owner of the current value, a `Shared<T>`, adding one to its count without waiting. `p.publish(v)` swaps in a new value and drops its own owner of the old one, which whoever drops the last owner destroys ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)), so a snapshot taken before the swap stays valid.
- **`Once<T>`** is set once. Its `get()` lends a read-only `Borrow<T>?`, `nil` until the value is set.
- **Blocking primitives** are `Event`, `Condvar` and `Semaphore`, whose waits park the thread ([below](#parking-and-waking-a-thread)), as a `Future`'s `wait()` does too, though a `Future` is an owned end and not `Synchronized` ([above](#futures)). An `Event` is set once: `signal()` wakes every thread parked in its `wait()`, and a later `wait()` returns at once. A `signal()` happens before every `wait()` it lets return, so what the signalling thread did before it is visible to the waiter. An `Event` holds only its state word, and declares no `deinit`, so destroying one runs no Rayo code.

**A `Condvar` wait consumes the guard and returns a new one:**

```swift
g = cv.wait(consume g)       // unlocks, parks, relocks after it wakes, and returns a new guard
```

`g` can be consumed only after the last use of every view derived from it, so no view of the protected data survives the unlock. The mutex is in the consumed guard's dependency set, so the wait borrows both the condvar and the mutex.

**The relock is the mutex's `lock`**, so it panics when another thread's panic poisoned the mutex during the wait ([above](#locks-mutex-and-rwlock)). The wait then doesn't return, and leaves the mutex unlocked.

**Poisoning wakes no thread.** A thread parked in a `Condvar` wait stays parked until another thread notifies the condvar, even when the panic it waited on has poisoned the mutex. So code that would notify does it in a `defer`, which runs on the unwind too ([Panics in lent work](thread-work.md#panics-in-lent-work)).

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

### Time: `Duration` and `Instant`

**std counts time in whole nanoseconds, held in an `Int64`, so times add and compare exactly on every target.** A `Duration` is a length of time, which every clock shares. An `Instant<Clock>` is a point in time on one clock, so the instants of two clocks have different types, and never mix:

```swift
struct Duration(let nanoseconds: Int64): Hashable, Comparable                     // may be negative; Duration.zero is no time
struct Instant<Clock: TimeSource>(let nanoseconds: Int64): Hashable, Comparable   // nanoseconds since Clock's own start

static func seconds(_ s: Double) -> Duration { … }              // Duration's: .seconds(0.5)
static func milliseconds(_ ms: Int64) -> Duration { … }         // Duration's, as are microseconds(_:) and nanoseconds(_:)
```

**A clock is a `TimeSource`, whose `now` is an instant of its own:**

```swift
protocol TimeSource { var now: Instant<Self> { get } }
struct MonotonicClock(): TimeSource { … }       // the system's clock for waits: MonotonicClock().now is an Instant<MonotonicClock>
```

**`MonotonicClock` is the clock of every wait on real time**: a timeout, `Thread.sleep(for:)`, and a task's `sleep(for:)` ([Awaitables in std](tasks.md#awaitables-in-std)). Its `now` never decreases, and how it relates to a calendar is left open. A program supplies other clocks as types of its own, such as a game whose simulation time stops while it is paused. Their instants can't reach a wait on real time, such as a `Waker`'s `wake(at:)`, which takes an `Instant<MonotonicClock>`.

**The arithmetic is `Int64` arithmetic on the nanoseconds**, so an overflow does what an `Int64` overflow does ([04](../04-types/numbers-and-math.md#integer-overflow-division-and-shifts)):

- two `Duration`s add and subtract, and a `Duration` multiplies by an `Int64`;
- an `Instant<C>` plus or minus a `Duration` is an `Instant<C>`;
- an `Instant<C>` minus an `Instant<C>` is the `Duration` between them.

**std's own waits saturate the deadlines they compute instead.** `sleep(for:)`, `elapsed(_:)`, `receive(timeout:)`, `Thread.sleep(for:)` and a park's `timeout` each add their `Duration` to `now` without overflowing. So a deadline past the end of `Instant`'s range never passes, and such a wait lasts until something else ends it.

**`seconds(_:)` rounds to the nearest nanosecond, ties to even**, which is IEEE 754's rounding to nearest, as a conversion to a floating-point type uses. It panics on NaN or on a value out of range, as converting a float to an integer does ([04](../04-types/numbers-and-math.md#conversions)).

**`Thread.sleep(for:)` parks the calling thread for at least `d`**, and returns at once when `d` is zero or less:

```swift
static func sleep(for d: Duration) { … }        // Thread's
```

### Parking and waking a thread

**A blocking primitive parks its waiting thread through the runtime**, which any `unsafe` code may call:

```swift
unsafe static func park(on word: *UInt32, expected: UInt32, timeout: Duration?) -> Bool { … }   // Runtime's: parks the calling thread on 'word'
unsafe static func wake(on word: *UInt32, count: Int) { … }                                      // Runtime's: wakes threads parked on 'word'
```

**`park` parks the calling thread on `word` if it still holds `expected`**, until another thread wakes it or `timeout` passes on `MonotonicClock` ([above](#time-duration-and-instant)). It returns `false` only when the timeout passed. It may also return early, so its caller checks its condition again. Its caller promises that `word` stays live and is accessed only atomically meanwhile.

**`wake` wakes up to `count` threads parked on `word`.**

**A parked thread keeps everything it holds**, so its live borrows still count as uses of their allocators ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).
