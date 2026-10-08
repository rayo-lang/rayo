# Arena safety and allocator lifetimes

[06 · Memory and allocators](../06-memory-and-allocators.md)

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

**A reset frees memory that values anywhere may still own, and it can't find those values or their views.** So two run-time checks keep it safe. The reset checks that nothing still uses the arena, which fails in the first example ([below](#what-a-reset-does)). Opening an owning value checks that no reset has invalidated its storage since it was allocated, which fails in the second ([below](#opening-an-owning-value-checks-it)).

### What a reset does

**`arena.reset()` frees everything the arena handed out, at once, after checking that nothing uses it.** It never waits: it panics instead, in every build, in these cases:

- **Any thread still uses the arena's memory.** Freeing the memory would leave that use reaching freed memory. The uses are:
  - an open of a value in it whose borrow is live ([below](#opening-an-owning-value-checks-it));
  - a pin into it, which holds the memory for C ([03](../03-handles-and-objects.md#pinning-for-c));
  - an object in it that an access holds, or whose home thread is another thread. Its `deinit` would run under that access, or off the one thread it may run on ([03](../03-handles-and-objects.md#objects-in-arenas-and-other-allocators)).
- **Another reset or unregistration that reaches the same memory is still running**, on any thread ([Allocators over other allocators](allocator-implementations.md#allocators-over-other-allocators)). So a reset that a `deinit` calls panics when the reset or unregistration running that `deinit` reaches the same memory.
- **The id is unregistered** ([below](#unregistering-an-allocator)).
- **The reset would exceed the arena's reset limit**, which keeps a word from being issued twice ([How values record their allocator](allocator-implementations.md#how-values-record-their-allocator)).
- **The allocator's kind isn't `.arena`**, `.system` included, since `reset()` and `release` ([Releasing a value without destroying it: `TrivialFree`](allocation-lifecycle.md#releasing-a-value-without-destroying-it-trivialfree)) are arena operations.

**What a reset changes, and what it costs:**

- **Values.** Every value allocated from the arena before the reset is **stale** from then on, including through a wrapper over it ([Allocators over other allocators](allocator-implementations.md#allocators-over-other-allocators)), and every value allocated after it is valid. An allocation racing the reset is ordered before it or after it.
- **Objects.** It destroys every object whose value lies in the arena, running their `deinit`s on the resetting thread before it frees their memory ([03](../03-handles-and-objects.md#objects-in-arenas-and-other-allocators)).
- **Cost.** A reset is O(1) in the number of values in the arena, and runs one `deinit` for each object in it that has one.

**The runtime carries out a reset, not the arena's implementation.** An arena hands out memory from blocks, each marked with a stamp. A **stamp** is an ordered token that the runtime issues, never the same one to two arenas, so a block's stamp also names its arena. The runtime decides which values are stale by the stamps of the blocks their storage lies in. Registering an arena calls `attachFresh(stamp:)` with its first stamp.

**A reset takes a new stamp `s`, later than every earlier one, and calls the `AllocatorImpl` hooks ([Writing an allocator: `AllocatorImpl`](allocator-implementations.md#writing-an-allocator-allocatorimpl)) in this order:**

1. `attachFresh(stamp: s)`: the arena serves new allocations from spare blocks, which it stamps `s`, or, with none, from new ones from its backing memory.
2. `backingDidSwitch(stamp: s)` on every wrapper over the arena.
3. Every value allocated from a block stamped before `s`, through the arena or a wrapper over it, is stale from now on.
4. It checks that nothing uses the old blocks, as above, and runs the `deinit`s of the objects in them ([below](#stale-values-and-the-deinits-a-reset-runs)).
5. `backingDidFree(stampedBefore: s)` on every wrapper over the arena, then `freeBlocks(stampedBefore: s)` on the arena, which keeps those blocks as spares or returns them to its backing memory.

**The order keeps a reset safe against a racing open and against the `deinit`s it runs.** The old values go stale (step 3) before the reset checks for uses (step 4), so an open racing the reset either fails or is counted ([below](#opening-an-owning-value-checks-it)). The old blocks are freed (step 5) only after the `deinit`s that may still read them have returned ([below](#stale-values-and-the-deinits-a-reset-runs)).

### Opening an owning value checks it

**Opening an owning value checks that no reset or unregistration has invalidated its storage since it was allocated.** A reset can't find the values allocated in the arena, which may be anywhere, so the check is made when each value is opened instead. A failure panics.

**The check covers every owning value, at every open:**

- **Owning values.** These are all values that own storage from an allocator, heap or arena: `List`, `String`, `Map`, `Box`, a `Closure`'s out-of-line context ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)), and the rest. An object's owner owns its object's storage but isn't an owning value in this sense. Its object is checked at each use instead, and destroyed by a reset ([03](../03-handles-and-objects.md#objects-in-arenas-and-other-allocators)).
- **Opening.** An open is any access that reaches storage the value owns:
  - reading or projecting what it holds, such as an element, a lookup, `Box.value`, a `Shared` value's contents or a `TrailingArray`'s header;
  - taking a span of it;
  - iterating it;
  - growing it;
  - calling a `Closure` whose context is out of line.

**For as long as what it lends is live, an open also counts as a use of the allocator**, which a reset or an unregistration checks for. A reset can't find the views of its values either, so each open counts itself until the last use of what depends on it, as a dynamic access is held ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). The counting follows two rules:

- **Counting uses.** An open of storage from any allocator but `.system`, which is never reset or unregistered, counts as a use of that allocator until the borrow it begins ends. That is the last use of everything that depends on what it lends ([02](../02-views-and-dependencies.md#dependencies)). Each thread keeps its own counts, so an open writes nothing other threads write, and only a reset or an unregistration reads every thread's.
- **Races are ordered.** An open fails when the reset or unregistration happens before it ([07](../07-concurrency/synchronization.md#atomics-and-locks)). A reset or an unregistration makes the storage stale before it reads the counts ([above](#what-a-reset-does), [below](#unregistering-an-allocator)). So an open and a reset or unregistration on two threads are ordered one way or the other:
  - the open comes first, and the reset or unregistration panics while what the open lends is live;
  - or the reset or unregistration comes first, and the open fails.

**The check is a memory-safety check, on in every build.** Only `unchecked` code strips it ([10](../10-errors-and-safety/checks-and-build-modes.md#unchecked-blocks)).

### Stale values, and the `deinit`s a reset runs

**Destroying a stale value never touches its memory, which may already be reused.** The exception is inside the `deinit` of an object that a reset or an unregistration destroys (below). Destroying a stale value skips both the free and its elements' `deinit`s. So a `deinit` may never run ([10](../10-errors-and-safety/unsafe-code.md#aliasing-and-skipped-deinits)), and anything those elements owned outside the invalidated allocator leaks.

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

- **What it owns stays usable to it.** While such a `deinit` runs, the thread running it can open a value that this reset or unregistration made stale. That holds for a reset or unregistration of the object's allocator, or of one it is built over ([Allocators over other allocators](allocator-implementations.md#allocators-over-other-allocators)). Freeing such a value from that `deinit` releases it into the allocator it came from. A value an earlier reset made stale still fails, since its memory may already be reused.
- **The memory is still there.** A reset frees its old blocks only after every such `deinit` has returned ([step 5](#what-a-reset-does)), and an unregistration destroys the implementation only then ([below](#unregistering-an-allocator)). So what an open lent inside one has ended first.

## Unregistering an allocator

```swift
let levelHeap = Allocator.register(TlsfHeap(size: 64.mb))
var props = List<Prop>(allocator: levelHeap)
// ... the level runs ...
Allocator.unregister(levelHeap)     // every value still allocated from the heap goes stale
props.append(p)                     // panics: 'props' came from an unregistered allocator
```

**`Allocator.unregister(a)` ends an allocator**, of any kind. A heap can't be reset, so unregistering it is how every value it handed out goes stale at once, as `props` does above.

- **It checks first, as a reset does** ([above](#what-a-reset-does)). Like a reset, it makes its values stale before it reads the counts of uses, so an open racing it either fails or is counted. It panics while any thread still uses its memory, or the memory of an allocator unregistered with it, through:
  - an open whose borrow is live;
  - a pin;
  - an object that an access holds, or whose home thread is another thread.

  It also panics while another reset or unregistration that reaches that memory is still running.
- **Its values go stale.** Heap or arena alike, its values go stale and its objects are destroyed, their `deinit`s running on the unregistering thread ([03](../03-handles-and-objects.md#objects-in-arenas-and-other-allocators)). Every allocator whose backing chain includes it is unregistered with it, since each draws its memory from it, directly or through others ([Allocators over other allocators](allocator-implementations.md#allocators-over-other-allocators)).
- **An unregistered id stays invalid.** Every allocator operation through it panics, in every build, however many allocators are registered later: allocating through it, resetting it and unregistering it again. The exceptions are:
  - freeing or growing a value that the unregistration made stale, from the `deinit` of an object the unregistration destroys ([above](#stale-values-and-the-deinits-a-reset-runs));
  - a forwarding `free` from the `deinit` of a wrapper unregistered with it, which does nothing (below).
- **Then the implementation is destroyed.** Once those `deinit`s have returned, it and every allocator unregistered with it are destroyed, those built on it first, releasing their memory. This comes last, since those `deinit`s may still read what they own from it ([above](#stale-values-and-the-deinits-a-reset-runs)).

  **Destroying a wrapper frees nothing in its backing on its own.** What it passed through stays allocated there unless its `deinit` frees it through the forwarding `free` ([Allocators over other allocators](allocator-implementations.md#allocators-over-other-allocators)). That `free` does nothing when the backing was unregistered with the wrapper, since the backing's own destruction then releases that memory.
