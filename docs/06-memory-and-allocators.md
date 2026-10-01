# 06 · Memory and allocators

```swift
let levelHeap = Allocator.register(TlsfHeap(size: 64.mb))   // a heap for level data
let scratch = Allocator.register(Arena(size: 64.mb))        // an arena for short-lived work

var props = List<Prop>(allocator: levelHeap)      // an allocator named explicitly
var names = List<String>()                        // the current allocator: .system unless a block says otherwise

using allocator = scratch {                       // everything built in here uses the scratch arena
    var visible = List<Handle<Mesh>>()            // no allocator parameter anywhere
    cull(scene, into: &visible)
    submit(visible.span)
}                                                 // 'visible' is destroyed here; freeing to an arena is a no-op

scratch.reset()                                   // everything the arena handed out is freed at once
```

Every heap allocation goes through an allocator the code can name, and every release happens at a point the code shows, where a value is destroyed: a scope end, an overwrite, a `consume`, a removal from a container, the drop of the last owner of a counted value ([below](#sharedt-data-with-many-owners)) or of the last pin ([03](03-handles-and-objects.md#pinning-for-c)), a thread's end ([07](07-concurrency.md#global-state)), an arena reset or an unregistration. No release frees memory that a view, on any thread, may still read: a reset or an unregistration checks first, and panics instead ([below](#arena-safety-checked-values-and-checked-resets)).

## Allocator values

**An `Allocator` is a copyable id that names a registered allocator implementation.** An owning container records the allocator its storage came from, and grows and frees through it, so the allocator isn't part of its type: a `List<Prop>` from `levelHeap` and one from `.system` are the same type.

- `.system`, the platform's general-purpose heap, has a fixed id and is never unregistered, so its storage never goes stale: `Allocator.unregister(.system)` panics. `Allocator.system` is a `static const`, so code takes it with no `copy` ([01](01-values-and-ownership.md#moving-values-out)): `Budgeted(inner: .system, …)`.
- Every other registered allocator, such as an arena, a heap or a budget wrapper, or one over a platform's memory APIs through `import c`, is library code implementing `AllocatorImpl` ([below](#writing-an-allocator-allocatorimpl)).

**Kinds.** A **heap**, such as `.system` or a TLSF heap, frees each allocation individually. An **arena** hands out memory from blocks and frees nothing individually: freeing into it is a no-op, and a **reset** frees everything it handed out at once ([below](#what-a-reset-does)). A **wrapper**, such as a budget or a tracking allocator, passes another allocator's allocations through and keeps accounts of them. An allocator may draw its memory from one other allocator, its **backing**, such as the allocator a wrapper wraps ([below](#allocators-over-other-allocators)).

## The current allocator

**Every thread has a current allocator, a thread-local that starts as `.system`, which constructors of allocating types record when they aren't given one, and which a closure's conversion into a `Closure` uses ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)).** It is consulted only then, a `clone()` included: a collection grows and frees through the allocator it was built with for its whole life, and `using allocator = .system { kept = scratch.clone() }` copies a value out of an arena.

- `using allocator = a { … }` makes `a` the current allocator for the block, and restores the previous one on exit, including early return. It reads the id in `a` once, on entry, with no `copy` written, as a `static const` is taken ([01](01-values-and-ownership.md#moving-values-out)), and holds no borrow of `a`, so the block may contain an `await`, and reassigning `a` inside it doesn't change the block's allocator.
- A task suspended inside the block restores its owner's current allocator at the `await`, and makes `a` current again when it resumes ([07](07-concurrency.md#task-functions-explicitly-stepped-coroutines)). Destroying it while it is suspended there changes no thread's current allocator.

### The static allocator

```swift
const primes: List<Int> = makePrimes(below: 1000)    // built by the compiler; its buffer is in static data
var more = primes.clone()                            // the clone's buffer comes from the current allocator
more.append(1009)                                    // and grows there, as any list's does
```

**Values in static data carry the static allocator, which never allocates or frees at run time.** They are the `const`s, and the global `let`s evaluated at compile time that pass the freezable test ([07](07-concurrency.md#initialization-at-startup), [10](10-compile-time.md#consts-that-reach-run-time)). Nothing consumes or mutates a value in static data, so it is never grown, and it is never destroyed ([10](10-compile-time.md#consts-that-reach-run-time)).

## Allocators and threads

**Every registered allocator must be safe to call from any thread**, since any thread can allocate through a copyable `Allocator` id, including lent work ([07](07-concurrency.md#lending-work-to-other-threads)). `AllocatorImpl` refines `Synchronized` ([07](07-concurrency.md#the-synchronized-contract)): its methods are non-`mutating`, and change what they change through their own synchronization: atomics, a lock, or state kept per thread inside the implementation.

## Arena safety: checked values and checked resets

```swift
let levelArena = Allocator.register(Arena(size: 256.mb))
var spawns = List<Vec3>(allocator: levelArena)
spawns.append(.zero)

let pts = spawns.span         // a view into the arena's memory, which the arena counts as a use
levelArena.reset()            // panics: 'pts' is used below, so something still uses the arena
print(pts[0])
```

```swift
print(spawns[0])              // the open ends with its statement
levelArena.reset()            // fine: nothing uses the arena, whose memory is freed at once
spawns.append(.zero)          // panics: 'spawns' was allocated in 'levelArena' before its reset
```

### What a reset does

**`arena.reset()` frees everything the arena handed out, at once, after checking that nothing uses it. It never waits.** It panics, in every build, while any thread still uses the arena's memory: an open of a value in it whose borrow is live ([below](#opening-an-owning-value-checks-it)), a pin into it ([03](03-handles-and-objects.md#pinning-for-c)), or an object in it that an access holds or whose home thread is another thread ([03](03-handles-and-objects.md#objects-in-arenas-and-other-allocators)). It panics while another reset or unregistration that reaches the same memory is still running, on any thread, as one that a `deinit` it runs calls is ([below](#allocators-over-other-allocators)). It also panics through an unregistered id ([below](#unregistering-an-allocator)), past the reset limit ([below](#how-values-record-their-allocator)), and through an allocator whose kind isn't `.arena`, `.system` included, since `reset()` and `release` ([below](#releasing-a-value-without-destroying-it-trivialfree)) are arena operations.

- **Values.** Every value allocated from the arena before the reset is **stale** from then on, including through a wrapper over it ([below](#allocators-over-other-allocators)), and every value allocated after it is valid. An allocation racing the reset is ordered before it or after it.
- **Objects.** It destroys every object whose value lies in the arena, running their `deinit`s on the resetting thread before it frees their memory ([03](03-handles-and-objects.md#objects-in-arenas-and-other-allocators)).
- **Cost.** A reset is O(1) in the number of values in the arena, and runs one `deinit` for each object in it that has one.

**The runtime carries out a reset, not the arena's implementation.** An arena hands out memory from blocks, each marked with a **stamp**, an ordered token the runtime issues, never the same one to two arenas, so a block's stamp also names its arena. Registering an arena calls `attachFresh(stamp:)` with its first stamp, and a reset calls the `AllocatorImpl` hooks ([below](#writing-an-allocator-allocatorimpl)) in this order, with a new stamp `s` later than every earlier one:

1. `attachFresh(stamp: s)`: the arena serves new allocations from spare blocks, which it stamps `s`, or, with none, from new ones from its backing memory.
2. `backingDidSwitch(stamp: s)` on every wrapper over the arena.
3. Every value allocated from a block stamped before `s`, through the arena or a wrapper over it, is stale from now on.
4. It checks that nothing uses the old blocks, as above, and runs the `deinit`s of the objects in them ([below](#stale-values-and-the-deinits-a-reset-runs)).
5. `backingDidFree(stampedBefore: s)` on every wrapper over the arena, then `freeBlocks(stampedBefore: s)` on the arena, which keeps those blocks as spares or returns them to its backing memory.

### Opening an owning value checks it

**Opening an owning value checks that no reset or unregistration has invalidated its storage since it was allocated**, since a reset can't find the values allocated in the arena, which may be anywhere. **And for as long as what it lends is live, the open counts as a use of the allocator, which a reset or an unregistration checks for.**

- **Owning values.** These are all values that own storage from an allocator, heap or arena: `List`, `String`, `Map`, `Box`, a `Closure`'s out-of-line context ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)), and the rest. An object's owner owns its object's storage but isn't an owning value in this sense: its object is checked at each use, and destroyed by a reset, as [03](03-handles-and-objects.md#objects-in-arenas-and-other-allocators) says.
- **Opening.** An open is any access that reaches storage the value owns: reading or projecting what it holds, such as an element, a lookup, `Box.value`, a `Shared` value's contents or a `TrailingArray`'s header, taking a span of it, iterating it, growing it, or calling a `Closure` whose context is out of line.
- **A failure panics.**
- **Counting uses.** An open of storage from any allocator but `.system`, which is never reset or unregistered, counts as a use of that allocator until the borrow it begins ends: the last use of everything that depends on what it lends ([02](02-views-and-dependencies.md#dependencies)). Each thread keeps its own counts, so an open writes nothing other threads write, and only a reset or an unregistration reads every thread's.
- **Races are ordered.** An open fails when the reset or unregistration happens before it ([07](07-concurrency.md#atomics-and-locks)). An open and a reset or unregistration on two threads are ordered one way or the other: either the open comes first, and the reset or unregistration panics while what it lends is live, or the reset or unregistration comes first, and the open fails.
- **It is a memory-safety check, on in every build.** Only `unchecked` code strips it ([11](11-errors-and-safety.md#check-levels)).

### Stale values, and the `deinit`s a reset runs

**Destroying a stale value never touches its memory**, except in the `deinit` of an object that a reset or an unregistration destroys (below). It skips both the free and its elements' `deinit`s, so a `deinit` may never run ([11](11-errors-and-safety.md#unsafe-code)), and anything those elements owned outside the invalidated allocator leaks.

**An object's `deinit` that a reset or an unregistration runs can still read what it owns from that allocator:**

```swift
struct Door(var name: String) {
    deinit { print(name) }                    // runs inside the reset that destroys this door
}

var doors = List<UniquePointer<Door>>()       // built outside the block: its buffer isn't in the arena
using allocator = levelArena {
    for i in 0..<4 {
        doors.append(UniquePointer(Door(name: String("gate \(i)"))))   // the doors and their names come from the arena
    }
}
levelArena.reset()                            // destroys the doors; each deinit can still read its 'name'
```

- **What it owns stays usable to it.** While such a `deinit` runs, opening a value that this reset or unregistration of the object's allocator, or of one it is built over ([below](#allocators-over-other-allocators)), made stale succeeds on the thread running it, and freeing one releases it into the allocator it came from. A value an earlier reset made stale still fails, since its memory may already be reused.
- **The memory is still there.** A reset frees its old blocks only after every such `deinit` has returned ([step 5](#what-a-reset-does)), and an unregistration destroys the implementation only then ([below](#unregistering-an-allocator)), so what an open lent inside one has ended first.

## Unregistering an allocator

```swift
let levelHeap = Allocator.register(TlsfHeap(size: 64.mb))
var props = List<Prop>(allocator: levelHeap)
// ... the level runs ...
Allocator.unregister(levelHeap)     // every value still allocated from the heap goes stale
props.append(p)                     // panics: 'props' came from an unregistered allocator
```

**`Allocator.unregister(a)` ends an allocator.**

- **It checks first, as a reset does.** It panics while any thread still uses its memory, or the memory of an allocator unregistered with it: an open whose borrow is live, a pin, or an object that an access holds or whose home thread is another thread, and while another reset or unregistration that reaches that memory is still running ([above](#what-a-reset-does)).
- **Its values go stale.** Heap or arena alike, its values go stale and its objects are destroyed, their `deinit`s running on the unregistering thread ([03](03-handles-and-objects.md#objects-in-arenas-and-other-allocators)). Every allocator whose backing chain includes it is unregistered with it.
- **An unregistered id stays invalid.** Every allocator operation through it panics, in every build, however many allocators are registered later: allocating through it, resetting it and unregistering it again. The exceptions are freeing or growing, from the `deinit` of an object the unregistration destroys, a value that the unregistration made stale ([above](#stale-values-and-the-deinits-a-reset-runs)), and a forwarding `free` from the `deinit` of a wrapper unregistered with it, which does nothing (below).
- **Then the implementation is destroyed.** Once those `deinit`s have returned, it and every allocator unregistered with it are destroyed, those built on it first, releasing their memory.

  Destroying a wrapper frees nothing in its backing on its own: what it passed through stays allocated there unless its `deinit` frees it through the forwarding `free` ([below](#allocators-over-other-allocators)), which does nothing when the backing was unregistered with it, since the backing's own destruction then releases that memory.

## How values record their allocator

**Every owning value records the allocator its storage came from in an allocator word**, which also dates the storage against that allocator's resets; a container of several allocations may keep several ([below](#a-containers-words-must-cover-all-of-its-storage)). A word is 8 bytes and opaque: only the runtime reads it, and C sees it as a `uint64_t` ([09](09-c-interop.md)).

- **Raw allocations.** They carry their word too, which an `unsafe` core stores next to its pointer ([11](11-errors-and-safety.md#unsafe-code)).
- **A stale word never passes.** Storage that a reset or an unregistration invalidated fails its check for good, however many allocators are registered, reset and unregistered later, outside the `deinit`s that a reset or an unregistration runs ([above](#stale-values-and-the-deinits-a-reset-runs)).
- **Limits.** How many allocators may be registered at once and over the program's run, and how many times one may be reset, are implementation-defined. Registering or resetting past a limit panics, in every build, so a word is never issued twice.

### A container's words must cover all of its storage

Every open of a container must fail whenever [Opening an owning value checks it](#opening-an-owning-value-checks-it) says an open of the storage it reaches, or of storage it needs to reach that, fails. So every owning container, std's, the builtin `SoA` or a user `unsafe` core, keeps words that cover all of its storage. A container of several allocations, such as a `Map`'s index and entries, may take them all from one allocator and record the word of the oldest, or keep one word per allocation, and a `StablePool`, which can't move its elements, keeps a word per page ([03](03-handles-and-objects.md#pools-and-handles)).

## Allocators over other allocators

```swift
let levelArena = Allocator.register(Arena(size: 256.mb))
let propBudget = Allocator.register(Budgeted(inner: copy levelArena, limit: 16.mb, name: "Props"))   // a wrapper over levelArena

var props = List<Prop>(allocator: propBudget)    // counted against the budget, stored in levelArena's blocks
levelArena.reset()                               // 'props' goes stale with the arena memory under it
```

**Any allocator may declare a `backing`, the one allocator it draws its memory from**, such as the allocator a budget wraps or the heap of device memory an arena takes its blocks from, so that a reset or an unregistration reaches everything built on it. What it reports depends on its kind:

- A **wrapper** passes its backing's `Allocation` through unchanged, block included, so an object's value or a `StablePool` page allocated through a wrapper over an arena is tied to its arena block like any other ([03](03-handles-and-objects.md#objects-in-arenas-and-other-allocators)). Its allocations record the wrapper, so growth and frees go through its accounting, and it passes each call on through its backing id's forwarding methods ([below](#writing-an-allocator-allocatorimpl)), which call the backing's implementation with the same arguments and return its result unchanged. They are `unsafe`, and their caller promises to be an implementation calling its own `backing`, since what they return carries no allocator word; they panic through an unregistered id as every allocator operation does, apart from the frees and growths [Unregistering an allocator](#unregistering-an-allocator) allows.
    - **Over an arena**, its allocations are valid until a reset frees the arena memory under them or the wrapper is unregistered. `backingDidSwitch` and `backingDidFree` tell it when memory stops existing, so it can keep its accounts per stamp.
    - **Over a heap**, its allocations go stale when it or the heap is unregistered.
- An **arena or heap with a backing**, such as an arena over device memory or a TLSF heap carved out of a larger one, draws from its backing and hands out memory of its own: an arena in its own blocks, which its own resets free, and a heap whose values go stale when it is unregistered. It keeps what it drew as long as it likes, so its backing chain must not include an arena, whose reset would reuse that memory under it.
- An allocator with **no `backing`** draws from `.system`, which is never reset or unregistered, or from platform memory it reserved ([below](#what-conforming-promises)), so no other allocator's reset or unregistration reaches what it handed out.

**Chains are fixed and acyclic.**

- `backing` names an allocator registered before it, and never changes while it is registered ([below](#what-conforming-promises)).
- Registering panics when the backing is already unregistered, or when an arena or heap's backing chain includes an arena. A registration racing with its backing's unregistration is ordered before it, and unregistered with it, or after it, and panics.

## Writing an allocator: `AllocatorImpl`

An implementation hands out memory and reports what it handed out. The runtime decides when that memory stops being valid ([above](#what-a-reset-does)).

```swift
unsafe protocol AllocatorImpl: Synchronized {          // must be callable from any thread
    var kind: AllocatorKind { get }                    // a wrapper passes its backing's allocations through
    var backing: Allocator? { get }                    // the one allocator this draws its memory from, or nil
    // The rest are unsafe to call: containers reach allocate, reallocate and free through the Allocator id's
    // allocateRaw, reallocateRaw and freeRaw (11), an implementation reaches its backing's through the id's
    // forwarding methods (below), and only the runtime calls the reset hooks.
    unsafe func allocate(bytes: Int, align: Int, site: CallSite) -> Allocation?   // address, plus the arena block it lies in, if any
    unsafe func reallocate(_ p: *Void, old: Int, new: Int, align: Int, site: CallSite) -> Allocation?
    unsafe func free(_ p: *Void, bytes: Int, align: Int)   // arenas: no-op
    unsafe func attachFresh(stamp: Stamp)              // arenas: from now on, serve from spare blocks stamped `stamp`
    unsafe func freeBlocks(stampedBefore: Stamp)       // arenas: every older block is free; keep it as a spare or give it back
    unsafe func backingDidSwitch(stamp: Stamp)         // wrappers: the backing arena now serves fresh blocks stamped `stamp`
    unsafe func backingDidFree(stampedBefore: Stamp)   // wrappers: memory stamped before `stampedBefore` is gone; newer memory isn't
}

struct Allocation(
    let address: *Void,
    let block: *BlockHeader?,                          // the arena block, which records its stamp, and so its arena; else nil
)

enum AllocatorKind { case heap, arena, wrapper }
struct Allocator(…): Copyable, Hashable               // an opaque id of a registered allocator; 8 bytes, 8-aligned
extension Allocator {                                  // forwarding: call the registered implementation's own methods
    unsafe func allocate(bytes: Int, align: Int, site: CallSite) -> Allocation?
    unsafe func reallocate(_ p: *Void, old: Int, new: Int, align: Int, site: CallSite) -> Allocation?
    unsafe func free(_ p: *Void, bytes: Int, align: Int)
}

struct Stamp(…): Copyable, Comparable                  // an opaque, ordered token; only the runtime makes one; 8 bytes, 8-aligned
struct CallSite(let id: UInt32): Copyable              // the allocating call site, which a build may pass so a tracking allocator
                                                       //   can attribute memory, or 0 where it passes none
struct BlockHeader(…)                                  // runtime-defined; starts every arena block.
                                                       //   An arena writes one with unsafe BlockHeader.initialize(at:stamp:)
```

### What conforming promises

**Conforming to `AllocatorImpl` is an `unsafe` promise to follow this contract:**

- `allocate` returns at least `bytes` bytes aligned to `align`, disjoint from every other live allocation. `reallocate` returns the same for `new` bytes, keeps the first `min(old, new)` of them, and frees the old ones when it moves them; when it returns `nil`, the old allocation stays live and unchanged.
- `free` and `reallocate` accept every allocation of its own that it handed out and that hasn't been freed, including one stamped before a reset in progress, which the `deinit`s that reset runs may still free or grow ([above](#stale-values-and-the-deinits-a-reset-runs)). It never grows such an allocation in place: it moves it.
- It never reuses memory on its own after handing it over, and reports blocks truthfully. An arena writes no block stamped before a reset until that reset calls `freeBlocks`.
- `kind` and `backing` never change while it is registered.
- It draws memory only from its declared `backing`, or, with none, from `.system` or platform memory it reserved itself, never from another registered allocator, which could be reset or unregistered under it.

## Owning boxes

```swift
enum Tree { case leaf(Int); case node(Box<Tree>, Box<Tree>) }   // recursion goes through a Box
let rock = Shared(loadTexture("rock.tex"))                      // immutable, with any number of owners
```

| Type | Semantics |
| --- | --- |
| `Box<T>` | Unique owning pointer, move-only. `Box.leak`, for a `T: ~Scoped`, gives up ownership and returns the `RawAllocation` that holds the value, with its address, size, alignment and allocator word ([11](11-errors-and-safety.md#unsafe-code)), for C to hold. `Box.adopt` (`unsafe`) takes it back, and its caller promises that it came from leaking a `Box<T>` and is adopted at most once |
| `UniquePointer<T>` | Unique owner of an object, on one thread; hands out checked `WeakPointer<T>`s ([03](03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)) |
| `Shared<T>` | Counted owner of a `Frozen` or `Synchronized` `T`, with an atomic count; hands out checked `WeakShared<T>`s |
| `LocalShared<T>` | Counted owner of a `Frozen` `T`, with a plain count, on one thread |

### `Shared<T>`: data with many owners

`Shared<T>` counts the owners of a value that many places, on any threads, hold at once:

```swift
struct Texture(var pixels: List<UInt8>, var width: Int)                // Frozen: derived by the compiler
struct Material(var albedo: Shared<Texture>, var roughness: Float)      // Frozen too, since Shared<Texture> is

let rock = Shared(Texture(pixels: loadPixels("rock.tex"), width: 512))
let wet = Shared(Material(albedo: rock.share(), roughness: 0.2))       // share() adds an owner, visibly
let dry = Shared(Material(albedo: consume rock, roughness: 0.9))       // a move: the count doesn't change

let log = Shared(Mutex(List<Message>()))                               // Synchronized: changes only under its lock
log.value.lock { $0.append(m) }
```

**A `Shared<T>`'s count is atomic, and its `T` must be `Frozen`** ([below](#frozen-types-with-no-interior-mutability)) **or `Synchronized`** ([07](07-concurrency.md#the-synchronized-contract)), so any number of threads may read the value at once, and it changes only through its own synchronization, if at all. **`LocalShared<T>`** is the same with a plain count, for a `Frozen` `T` only, and with no weak links: it is never `Sendable`, so all its owners stay on one thread and counting needs no atomic operation.

- **Counting is visible.** Both are move-only, and each new owner takes an explicit `s.share()`. A move doesn't change the count. `s.value` lends the value read-only for as long as `s` is borrowed.
- **The last owner destroys the value.** Dropping the owner that takes the count to zero runs the value's `deinit` and frees its memory at once, on the thread that dropped it.
- **Cycles.** A `Frozen` value never changes, and neither does anything it owns, so a `Shared` of one can only point at values that existed before it, and nothing it owns can be changed to point back: **immutable counted values can't form cycles.** A `Synchronized` value can be changed to hold an owner of itself, as a `Shared<Mutex<Node>>` can, and that cycle leaks.
- **Weak links.** `s.weak()` on a `Shared<T>` returns a **`WeakShared<T>`**: 8 bytes and copyable, and it doesn't keep the value alive. `w.upgrade()` returns a new owner, a `Shared<T>?`, through an atomic compare-and-swap, never waiting for another thread, and reads `nil` once the value is destroyed or its storage stale ([above](#opening-an-owning-value-checks-it)). A weak link names its value by a generation that no other `Shared` value of the run gets, so it never names a later one, and `w.bits` packs it into a `UInt64` that `WeakShared<T>(bits:)` checks as `WeakPointer<T>(bits:)` does, without the thread ([03](03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c)). `WeakShared<any P>` holds an existential as `WeakPointer<any P>` does ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).
- **Handing an owner to C.** `Shared.leak(s)` gives up the owner, keeping its count, and returns a weak link for C to hold as a `uint64_t`. `Shared.adopt(w)` returns that owner, and reads `nil` unless `w` names a live value with a leaked owner, so a forged, mistyped or repeated `adopt` is harmless. While C holds a leaked owner, the value stays at its address.
- **Threads.** `Shared<T>` and `WeakShared<T>` are `Sendable` when `T` is, and `LocalShared<T>` never is ([07](07-concurrency.md#what-may-cross-threads-sendable)). Weak pointers and weak links don't own, so a `Frozen` value may hold them without creating cycles, and one that crosses threads holds only weak links, since an object's weak pointers stay on its home thread.
- **Other counts.** `Sender`, `Receiver` and `Future` values also count their owners internally, and [07](07-concurrency.md#queues-and-channels) says which of their cycles dropping a `Receiver` breaks; the others leak.

### `Frozen`: types with no interior mutability

**The compiler derives `Frozen` for types with no interior mutability:** no `Synchronized` fields (no `Mutex`, `Atomic` or queue), no object owners (whose objects are mutable through weak pointers), no raw pointers, and no `Closure`s. **Nothing that is or holds a `Synchronized` value, at any depth, is `Frozen`**, whatever the `Synchronized` type's own fields look like, since its non-`mutating` methods write it ([07](07-concurrency.md#the-synchronized-contract)), and declaring `: unsafe Frozen` on such a type is a compile error.

- **What it covers.** Nothing writes a `Frozen` value's fields, or any buffer it owns, through a shared borrow of it: only bookkeeping that no reader observes, such as a `Shared`'s count, changes under one. Its owner may still mutate it, as a `var` of it. A weak pointer, a weak link or a handle in it only names another value, which isn't part of it and may change.
- **Declaring it.** A type the compiler can't derive it for, typically one holding a raw pointer to data that never changes, may declare `: unsafe Frozen`, an unverified promise ([11](11-errors-and-safety.md#safe-modules)) that nothing writes what it holds, or what it points at through a raw pointer, through a shared borrow of it, except bookkeeping that no reader observes, and that nothing at all writes a value of it frozen into read-only data ([10](10-compile-time.md#consts-that-reach-run-time)). So a type that writes bookkeeping must keep its values from being freezable, as a `Shared` does by not being `TrivialFree`. The language makes it for `StaticSpan` and `StaticString`, which point into immortal read-only data.
- **Existentials.** An existential has no fields to check, so `any P` and `mutable any P` are `Frozen` only when `P` refines `Frozen`, or when they are written with `& Frozen`, which accepts only `Frozen` types, as for `Sendable` ([07](07-concurrency.md#what-may-cross-threads-sendable)).
- **Containers.** std's owning containers (`List`, `String`, `Map`, `Set`, `TrailingArray`, `Pool`, `StablePool`, `Box` and `Blob`) and the builtin `SoA` conform when every type they hold does: a `TrailingArray`'s header and elements, a `Map`'s keys and values, and each other container's elements. So `Box<any P>` is `Frozen` exactly when its `any P` is. The raw pointer inside each names a buffer the container owns alone, written only by its `mutating` methods, which need exclusive access that no shared borrow of a `Frozen` holder grants, apart from a `StablePool`'s pin counts (below), or, in a `String` made from a literal, immortal bytes nothing writes ([04](04-types.md#literals)).
- **`Shared<T>` and `LocalShared<T>`.** Each is `Frozen` when its `T` is: its count is bookkeeping that no reader observes. So an asset graph, a `Shared<Material>` holding `Shared<Texture>`s, is `Frozen` all the way down. A `StablePool`'s pin counts are bookkeeping of the same kind ([03](03-handles-and-objects.md#pinning-for-c)), so pinning an element of a `Frozen` pool, from any thread, leaves it `Frozen`.

## Long-lived views into long-lived buffers

For a view that has to be stored in long-lived state, which a scoped `Span` can't be ([02](02-views-and-dependencies.md#scoped-values)), the buffer lives behind a `Shared` ([above](#sharedt-data-with-many-owners)), as a fixed-size **`Blob`** of bytes, or a `Blob` or `List` under an `RwLock`, and the view is a checked **`Slice<T>`**:

```swift
let package = Shared(try Blob.load("level3.pak"))       // Blob: fixed-size bytes, 16-byte-aligned unless asked
struct MeshComponent(var vertices: Slice<Vertex>)        // a checked view: a weak link to the buffer and an element range

let m = MeshComponent(vertices: try package.slice(of: Vertex.self, at: header.vertexOffset, count: header.vertexCount))
upload(m.vertices.read()!)                               // Span<Vertex>: one check, then none per element
```

**`Slice<T>` is unscoped, copyable and `Sendable`. It holds a weak link to its buffer's `Shared`, so it keeps nothing alive, and once that value is destroyed every `Slice` into it reads `nil`.**

- **Reading and locking it.** `s.read()` gives a slice's elements as a `Span<T>?` and `s.lock()` as a `MutableSpan<T>?`, each `nil` once the buffer is gone: its `Shared` value destroyed, or the buffer's storage stale after a reset or an unregistration, which each call checks as an open does, reading `nil` where an open would panic ([above](#opening-an-owning-value-checks-it)). Each call upgrades the weak link, and the span holds that owner, and for a buffer under an `RwLock` its read lock for `read()` or its write lock for `lock()`, until its last use (rule 6 in [02](02-views-and-dependencies.md#dependencies)). A slice of a bare `Shared<Blob>` is read-only: its `lock()` panics, since nothing writes a `Frozen` value.
- **Blobs.** A `Blob` owns one allocation of bytes, with its length and alignment fixed at construction. The alignment is 16 bytes unless the constructor asks for more, up to the page size, as in `Blob(count: n, align: 64)`.
- **What creation checks.** `T` must be `Pod` ([04](04-types.md#plain-data-pod-and-bit-casts)), and a blob's bytes are always initialized (zeroed at construction, or filled by the load), so reading them as `T` is sound. `slice(of:at:count:)` throws unless the range is in bounds, `T`'s alignment is at most the blob's, and the offset is a multiple of `T`'s alignment. Locking as a `MutableSpan<T>` also requires `T.isPaddingFree`, as a mutable span cast does ([04](04-types.md#plain-data-pod-and-bit-casts)), since a store through a padded `T` would leave bytes other slices read uninitialized.
- **Locked blobs.** A slice of a `Shared<RwLock<Blob>>` is read and locked under the blob's lock. A write lock can **replace the whole blob** with a shorter or less-aligned one (`o.value.write { $0 = Blob(count: 16) }`), so each `read()` or `lock()` of such a slice also compares its end with the current blob's length, and `T`'s alignment with the blob's, under the lock it takes anyway. A failure reads as `nil`. A bare `Shared<Blob>` can't be replaced, so the range and alignment creation checked hold for its slices' whole life.
- **Lists.** `o.slice(at:count:)` on a `Shared<RwLock<List<T>>>` makes a `Slice<T>` of a range of its elements, which needn't be `Pod`. A write lock can grow, shrink or move the list's buffer, so each `read()` or `lock()` of such a slice finds the buffer again and compares the range with the list's current count, under the lock it takes. A failure reads as `nil`.
- **Limits.** `slice` throws when the offset or the count exceeds `UInt32.max`.

A `Font` owns its file's blob through a `Shared`, plus `Slice`s into it:

```swift
struct Font(
    var file: Shared<Blob>,          // an owner: the blob lives while any font that shares it does
    var glyphs: Slice<GlyphRecord>,  // stored views into that same blob
)
```

## Allocation failure

```swift
func addSpawn(_ p: Vec3, to spawns: mutable SoA<Vec3>) throws(AllocError) {
    do {
        try spawns.tryAppend(copy p)    // the fallible form: throws AllocError instead of panicking
    } catch {
        evictUnusedAssets()             // make room, then try once more
        try spawns.tryAppend(copy p)    // 'p' is borrowed, so each attempt appends a copy
    }
}
```

**An operation of the language's, or of a std type the language names, such as `Box` or `Shared` ([12](12-compilation-model.md#modules-and-names)), that allocates panics when its allocator can't make the allocation.** Those that build or grow a value at run time also have a fallible form, which throws `AllocError`, the prelude's error for an allocation its allocator couldn't make, or returns `nil`:

- `try Box.tryNew(v)`, `try Shared.tryNew(v)`, `try LocalShared.tryNew(v)` and `try UniquePointer.tryNew(v)`;
- `try Closure.tryNew { … }`, for a closure whose captures exceed the inline budget ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref));
- the builtin `SoA`'s growing operations, such as `try rows.tryAppend(x)` ([04](04-types.md#struct-of-arrays-soat));
- `Name(interning:)` ([04](04-types.md#collections-and-strings)), and `allocateRaw` and `reallocateRaw` ([11](11-errors-and-safety.md#unsafe-code)).

**`@noalloc` on a function makes any call in it that may allocate a compile error:**

```swift
@noalloc
func fillSilence(_ out: mutable MutableSpan<Float>, _ history: mutable List<Float>) {
    for i in 0..<out.count { out[i] = 0 }        // fine: nothing here allocates
    history.append(0)                            // error: 'append' may allocate, and 'fillSilence' is @noalloc
}
```

**What may allocate.** In a `@noalloc` function, a call may allocate unless its callee is known statically and is itself `@noalloc`, or is a language operation that doesn't allocate, such as integer arithmetic or indexing a span. That includes the calls the language makes for the code ([05](05-protocols-generics-and-closures.md#functions-and-closures)), so `[1, 2] as List<_>` is an error there ([04](04-types.md#literals)). A call through a function value may allocate unless its type is `@noalloc` ([05](05-protocols-generics-and-closures.md#function-typed-values)). A call through `any P`, and a requirement call in generic code, may allocate unless the protocol declares the requirement `@noalloc`, which every witness to it must then be.

**Destruction and C.** Destroying a value may allocate unless each `deinit` it runs, at any depth, is `@noalloc` or `PlainDeinit` ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)), since freeing memory isn't allocating. So destroying a value of a type parameter, or of a type that hides its value's `deinit`, such as a `Box<any P>` or a `Closure`, may allocate unless the type is `TrivialFree` ([below](#releasing-a-value-without-destroying-it-trivialfree)), or is a `Closure` whose function type is `@noalloc`, since only captures whose destruction passes the check move into one ([05](05-protocols-generics-and-closures.md#function-typed-values)). Dropping an object's owner may allocate, since it may run the object's `deinit`, and so may dropping a `Pin` or a `LocalPin`, since the last pin to drop runs the `deinit` its destruction left waiting. A call to C may allocate unless the import or the `extern c func` declares the function `noalloc` ([09](09-c-interop.md#c-calls-in-noalloc-code-noalloc)), or it goes through a `@c noalloc` pointer ([05](05-protocols-generics-and-closures.md#c-function-pointers)).

**Attaching a thread isn't covered.** A `@c` or `@export` function's first entry on a thread Rayo didn't create attaches that thread, which runs its thread-local initializers ([09](09-c-interop.md#calling-rayo-from-c)), and they may allocate, in a `@noalloc` function too.

## Releasing a value without destroying it: `TrivialFree`

```swift
using allocator = levelArena { world.level = loadLevel(3) }  // the level's lists and strings come from the arena

levelArena.release(replace(&world.level, with: Level()))     // requires Level: TrivialFree; forgets the old level instead of destroying it
levelArena.reset()                                           // what the arena holds goes stale, and its memory is freed
```

`TrivialFree` is a language marker protocol that the compiler **derives**, as it derives `Frozen`, for a type whose destruction does nothing but free memory: every `deinit` in it, at any depth, is `PlainDeinit` ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)). So it holds no object owner, which destroys its object, no `Pin` or `LocalPin`, which unpins, and no counted owner such as a `Shared`. A value whose `deinit` its type hides counts too: `Box<any P>` is `TrivialFree` only when `P` refines `TrivialFree` or it is written `Box<any P & TrivialFree>`, as for `Frozen` ([above](#frozen-types-with-no-interior-mutability)), and a `consuming` function value and a `Closure<F>`, which may own handed-over captures ([05](05-protocols-generics-and-closures.md#function-typed-values)), never are.

`release` forgets the value instead of destroying it, and `reset` makes the memory reusable. Anything the value owns that didn't come from the arena leaks, and `release` `assert`s that nothing does ([11](11-errors-and-safety.md#assert-and-precondition)).
