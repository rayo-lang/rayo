# Allocator storage and implementations

[06 · Memory and allocators](../06-memory-and-allocators.md)

## How values record their allocator

**Every owning value records the allocator its storage came from in an allocator word**, which also dates the storage against that allocator's resets. The word is how the value grows and frees through its own allocator, and what an open checks ([Opening an owning value checks it](arena-safety.md#opening-an-owning-value-checks-it)). A container of several allocations may keep several ([below](#a-containers-words-must-cover-all-of-its-storage)). A word is 8 bytes and opaque: only the runtime reads it, and C sees it as a `uint64_t` ([08](../08-c-interop.md)).

- **Raw allocations.** They carry their word too, which an `unsafe` core stores next to its pointer ([10](../10-errors-and-safety/unsafe-code.md#raw-allocations)).
- **A stale word never passes.** Storage that a reset or an unregistration invalidated fails its check for good, however many allocators are registered, reset and unregistered later, outside the `deinit`s that a reset or an unregistration runs ([Stale values, and the `deinit`s a reset runs](arena-safety.md#stale-values-and-the-deinits-a-reset-runs)).
- **Limits.** How many allocators may be registered at once and over the program's run, and how many times one may be reset, are implementation-defined. Registering or resetting past a limit panics, in every build, so a word is never issued twice, and a stale one never passes again.

### A container's words must cover all of its storage

**An open of a container must fail whenever an open of the storage it reaches would fail, or of the storage it needs in order to reach that storage** ([Opening an owning value checks it](arena-safety.md#opening-an-owning-value-checks-it)). Otherwise the open could pass and then read a stale buffer, whose memory may already be reused. So every owning container keeps words that cover all of its storage, whether it is std's, the builtin `SoA` or a user `unsafe` core:

- **One word for several allocations.** A container of several allocations, such as a `Map`'s index and entries, may take them all from one allocator and record the word of the oldest. A reset or an unregistration that makes any of them stale makes the oldest stale too.
- **A word per allocation.** It may instead keep one word per allocation.
- **A word per page.** A `StablePool`, which can't move its elements, keeps a word per page ([03](../03-handles-and-objects.md#pools-and-handles)).

## Allocators over other allocators

```swift
let levelArena = Allocator.register(Arena(size: 256.mb))
let propBudget = Allocator.register(Budgeted(inner: copy levelArena, limit: 16.mb, name: "Props"))   // a wrapper over levelArena

var props = List<Prop>(allocator: propBudget)    // counted against the budget, stored in levelArena's blocks
levelArena.reset()                               // 'props' goes stale with the arena memory under it
```

**Any allocator may declare a `backing`, the one allocator it draws its memory from.** Examples are the allocator a budget wraps, and the heap of device memory an arena takes its blocks from. Declaring it lets a reset or an unregistration of the backing reach everything built on it. What an allocator reports depends on its kind:

- A **wrapper** passes its backing's `Allocation` through unchanged, block included. So an object's value or a `StablePool` page allocated through a wrapper over an arena is tied to its arena block like any other ([03](../03-handles-and-objects.md#objects-in-arenas-and-other-allocators)). Its allocations record the wrapper, so growth and frees go through its accounting.

    It passes each call on through its backing id's forwarding methods ([below](#writing-an-allocator-allocatorimpl)), which call the backing's implementation with the same arguments and return its result unchanged. They are `unsafe`, and their caller promises to be an implementation calling its own `backing`, since what they return carries no allocator word. They panic through an unregistered id as every allocator operation does, apart from the frees and growths that unregistering allows ([Unregistering an allocator](arena-safety.md#unregistering-an-allocator)).
    - **Over an arena**, its allocations are valid until a reset frees the arena memory under them or the wrapper is unregistered. `backingDidSwitch` and `backingDidFree` tell it when memory stops existing, so it can keep its accounts per stamp.
    - **Over a heap**, its allocations go stale when it or the heap is unregistered.
- An **arena or heap with a backing** draws from its backing and hands out memory of its own, as an arena over device memory or a TLSF heap carved out of a larger one does. Such an arena hands it out in its own blocks, which its own resets free. Such a heap's values go stale when it is unregistered. Either keeps what it drew as long as it likes, so its backing chain must not include an arena, whose reset would reuse that memory under it.
- An allocator with **no `backing`** draws from `.system`, which is never reset or unregistered, or from platform memory it reserved ([below](#what-conforming-promises)), so no other allocator's reset or unregistration reaches what it handed out.

**Chains are fixed and acyclic**, so a reset or an unregistration of an allocator reaches everything built on it:

- `backing` names an allocator registered before it, which rules out a cycle, and never changes while it is registered ([below](#what-conforming-promises)).
- Registering panics when the backing is already unregistered, or when an arena or heap's backing chain includes an arena. A registration racing with its backing's unregistration is ordered before it, and unregistered with it, or after it, and panics.

## Writing an allocator: `AllocatorImpl`

**An implementation hands out memory and reports what it handed out.** The runtime decides when that memory stops being valid ([What a reset does](arena-safety.md#what-a-reset-does)). A library adds an allocator by registering a value of a type that conforms, and gets back the `Allocator` id that names it.

```swift
unsafe protocol AllocatorImpl: Synchronized {          // must be callable from any thread
    var kind: AllocatorKind { get }                    // a wrapper passes its backing's allocations through
    var backing: Allocator? { get }                    // the one allocator this draws its memory from, or nil
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

**The members other than `kind` and `backing` are `unsafe` to call, and code reaches them in three ways:**

- containers reach `allocate`, `reallocate` and `free` through the `Allocator` id's `allocateRaw`, `reallocateRaw` and `freeRaw` ([10](../10-errors-and-safety/unsafe-code.md#raw-allocations));
- an implementation reaches its backing's through the id's forwarding methods ([above](#allocators-over-other-allocators));
- only the runtime calls the hooks a reset uses: `attachFresh`, `backingDidSwitch`, `backingDidFree` and `freeBlocks`.

### What conforming promises

**Conforming to `AllocatorImpl` is an `unsafe` promise to follow this contract:**

- **Allocating.** `allocate` returns at least `bytes` bytes aligned to `align`, disjoint from every other live allocation. `reallocate` returns the same for `new` bytes, keeps the first `min(old, new)` of them, and frees the old ones when it moves them. When it returns `nil`, the old allocation stays live and unchanged.
- **Freeing and growing.** `free` and `reallocate` accept every allocation of its own that it handed out and that hasn't been freed. That includes one stamped before a reset in progress, which the `deinit`s that reset runs may still free or grow ([Stale values, and the `deinit`s a reset runs](arena-safety.md#stale-values-and-the-deinits-a-reset-runs)). It never grows such an allocation in place: it moves it.
- **Reuse and reports.** It never reuses memory on its own after handing it over, and reports blocks truthfully, since the runtime decides by a block's stamp which values are stale ([What a reset does](arena-safety.md#what-a-reset-does)). An arena writes no block stamped before a reset until that reset calls `freeBlocks`, since the `deinit`s that reset runs may read those blocks until then.
- **A fixed shape.** `kind` and `backing` never change while it is registered, which keeps its backing chain fixed ([above](#allocators-over-other-allocators)).
- **Where its memory comes from.** It draws memory only from its declared `backing`, or, with none, from `.system` or platform memory it reserved itself. It never draws from another registered allocator, which could be reset or unregistered under it.
