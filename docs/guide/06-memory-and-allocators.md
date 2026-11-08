# 6 · Memory and allocators

The game now needs memory at two speeds. Its meshes, the shapes it draws, live until the level unloads. Each frame's scratch data, such as the list of meshes the camera sees, lives for one frame. An arena suits the scratch: it frees nothing one value at a time, and frees everything it gave out at once, when you reset it.

```swift
let levelHeap = Allocator.register(TlsfHeap(size: 256.mb))   // the level's data
let frameArena = Allocator.register(Arena(size: 64.mb))      // scratch data, freed every frame

while running {
    using allocator = frameArena {                           // what this block builds comes from the arena
        var visible = List<Handle<Mesh>>()
        cull(world, into: &visible)
        submit(visible.span)
    }                                                        // 'visible' is destroyed: freeing into an arena does nothing
    frameArena.reset()                                       // the frame's scratch memory is freed at once
}
```

In C++, a pointer that survives into the next frame is a silent use-after-free: the arena hands its memory out again, and the old pointer reads whatever is there now. Rayo keeps the arena and its one-step free, and turns that bug into a panic at the line that would read reused memory.

## Allocators are values

```swift
var levelMeshes = List<Mesh>(allocator: levelHeap)   // grows and frees through levelHeap, for its whole life
var editorMeshes = List<Mesh>(allocator: .system)    // the same type: List<Mesh>
var names = List<String>()                           // no allocator given: the current one (below)
```

Every heap allocation goes through an allocator the code can name ([06](../spec/06-memory-and-allocators.md)). `Allocator.register` takes an implementation, such as an `Arena`, and returns a copyable `Allocator` id. You pass that id when you want to choose where a value's storage lives. `.system` names the platform's general-purpose heap and is always available ([06](../spec/06-memory-and-allocators/allocator-basics.md#allocator-values)).

A list, string or box that owns allocated storage is an **owning value**. It records the allocator it used, then grows and frees through that allocator for its whole life ([06](../spec/06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator)). This is why `levelMeshes` and `editorMeshes` have the same type, `List<Mesh>`, despite using different heaps: a function that takes a `List<Mesh>` accepts either.

**Every registered allocator is one of three kinds:**

- A **heap**, such as `.system` or a TLSF heap, frees each allocation on its own.
- An **arena** frees nothing on its own. Freeing into it does nothing, and a **reset** frees everything it handed out at once.
- A **wrapper**, such as a memory budget, passes another allocator's allocations through and keeps accounts of them ([06](../spec/06-memory-and-allocators/allocator-implementations.md#allocators-over-other-allocators)).

**You can write an allocator of your own.** Every allocator but `.system` is library code that implements the `AllocatorImpl` protocol ([06](../spec/06-memory-and-allocators/allocator-implementations.md#writing-an-allocator-allocatorimpl)). Conforming is an `unsafe` promise to keep that protocol's contract, since the compiler can't check an allocator's bookkeeping ([06](../spec/06-memory-and-allocators/allocator-implementations.md#what-conforming-promises)).

**Every registered allocator must be safe to call from any thread**, since any thread can allocate through an id it holds.

## The current allocator

Each thread starts with `.system` as its current allocator. `using allocator = a { … }` changes that choice for its block and restores the previous one when the block exits, even by an early return ([06](../spec/06-memory-and-allocators/allocator-basics.md#the-current-allocator)). Code reads the current allocator when it builds new storage without naming another one. That includes:

- a constructor that isn't given an allocator, such as `List<Enemy>()`, `String("wave \(n)")` or `Box(e)`;
- a literal that builds a `List`;
- `clone()`, which builds its copy there;
- a closure stored as a `Closure` value, when what it captures doesn't fit inside it ([05](../spec/05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).

A list keeps the allocator it was built with, wherever it later grows. Entering a `using allocator` block does not change an existing list. It *does* affect a new string appended to that list:

```swift
var names = List<String>()                       // built outside the block: its buffer is in .system
using allocator = frameArena {
    names.append(String("wave \(wave)"))         // the list grows in .system, but the new String is in the arena
}
frameArena.reset()
print(names[0])                                  // panics: the string came from 'frameArena' before its reset
```

The current allocator belongs to the running thread. Work lent to another thread uses that thread's choice, which may differ from yours ([07](../spec/07-concurrency/thread-work.md#thread-locals-in-lent-work)). Chapter 7 shows how to lend work ([Concurrency](07-concurrency.md)).

## Arenas and resets

`arena.reset()` frees everything the arena handed out at once ([06](../spec/06-memory-and-allocators/arena-safety.md#what-a-reset-does)). A value allocated before the reset is then **stale**: its storage is gone and may be reused. A value allocated afterwards is valid. Two checks prevent stale storage from turning into a use-after-free, in every build:

- **Opening a stale value panics.** To open a value is to reach the storage it owns, as reading an element does ([below](#what-an-open-checks)).
- **A reset panics while anything, on any thread, still uses the arena's memory.** It never waits.

```swift
var positions = List<Vec3>(allocator: frameArena)
positions.append(.zero)

let pts = positions.span    // a view into the arena's memory: a use of the arena while 'pts' is live
frameArena.reset()          // panics: 'pts' is used below
print(pts[0])
```

```swift
print(positions[0])         // this use of the arena ends with its statement
frameArena.reset()          // fine: nothing uses the arena, and its memory is freed
positions.append(.zero)     // panics: 'positions' was allocated in 'frameArena' before its reset
```

Finish using the arena's memory before you reset it, and copy out anything the next frame needs ([below](#keeping-results-past-a-reset)). If worker threads use the arena, wait for their jobs to finish first. A reset while a job still reads it panics.

### What an open checks

An **open** is an access that reaches storage an owning value owns ([06](../spec/06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)). Opening a value includes:

- reading what it holds, such as an element or a `Box`'s value;
- taking a span of it;
- iterating it;
- growing it.

Each open checks whether the allocator has reset since the value obtained its storage, and panics if it has. Taking a span also counts as using the arena until the span's last use. That is why the reset beside `pts` fails even though the program has not yet read an element through `pts`. The spec gives the exact check and how it works across threads ([06](../spec/06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).

### Stale values, objects and heaps

**Destroying a stale value does nothing**, since its memory may already hold other values. It skips the free, and its elements' `deinit`s. So whatever those elements owned outside the arena leaks, and a value in an arena should own nothing outside it.

**A reset destroys the objects in the arena.** An object made with `UniquePointer(value, allocator: frameArena)` dies in the reset, which runs its `deinit` on the resetting thread. Its weak pointers read `nil` from then on.

**Inside that `deinit`, the object can still read what it owns from the arena** ([06](../spec/06-memory-and-allocators/arena-safety.md#stale-values-and-the-deinits-a-reset-runs)). The reset frees the arena's memory only after every such `deinit` has returned.

**A reset panics first if one of those objects is in use**: when an access to it is live, when it's pinned, or when its home thread is another thread ([03](../spec/03-handles-and-objects.md#objects-in-arenas-and-other-allocators)).

**Only an arena resets.** `reset()` on a heap, `.system` included, panics.

**A heap ends with `Allocator.unregister`** ([06](../spec/06-memory-and-allocators/arena-safety.md#unregistering-an-allocator)). When the level unloads, `Allocator.unregister(levelHeap)` checks for uses as a reset does. Then every value still allocated from the heap goes stale, and its objects are destroyed.

**An unregistered id stays invalid for good**, so nothing made from it ever passes its check again.

## Keeping results past a reset

```swift
using allocator = frameArena {
    var names = List<String>()
    collectNames(world, into: &names)                             // the list and its strings come from the arena
    using allocator = .system { world.results = names.clone() }   // the clone and its strings come from .system
}
frameArena.reset()
world.results.append(String("late"))                              // fine: nothing in it came from the arena
```

**To keep a value past a reset, build it in an allocator that outlives the reset.** `clone()` builds its copy in the current allocator, so a `using allocator = .system` block inside the arena's block copies a value out.

## One owned value: `Box`

The game gives its boss an allocation of its own:

```swift
var boss = Box(Enemy(pos: [0, 0, 40], hp: 5000))   // one allocation, from the current allocator
boss.value.hp -= 250                                 // changes the enemy in place
```

**`Box<T>` owns one value in an allocation of its own** ([06](../spec/06-memory-and-allocators/owning-values.md#owning-boxes)). It's move-only, and destroying it destroys its value and frees its memory.

**`box.value` reaches the value in place**, to read it or change it.

A `Box` also lets the game store a branching decision tree. A `Tree` value cannot directly contain another whole `Tree` value, since that would make its size endless. Boxes hold the child values in separate allocations:

```swift
enum Tree {
    case leaf(Int)
    case node(Box<Tree>, Box<Tree>)                 // the child trees live in separate allocations
}
```

**A recursive type goes through a `Box`.** The allocation shows in the type ([04](../spec/04-types/structs.md#structs)).

### Boxes of `any P`

**An existential, `any P`, holds a value of any type that conforms to the protocol `P`** ([05](../spec/05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)). It calls `P`'s requirements through a table, so the value's type can be one you know only at run time.

**A plain `any P` only borrows its value, as a view does.** To own a value whose type you know only at run time, put it in a box: a `Box<any P>`.

The game already has enemies that take damage. To put them in one list with breakable crates, give both types the same `Damageable` behavior:

```swift
protocol Damageable {
    mutating func takeDamage(_ amount: Float)
}

extension Enemy: Damageable {
    mutating func takeDamage(_ amount: Float) { hp -= amount }
}

struct Crate(var pos: Vec3, var hp: Float = 20)
extension Crate: Damageable {
    mutating func takeDamage(_ amount: Float) { hp -= amount }
}

var targets = List<Box<any Damageable>>()
targets.append(Box(Enemy(pos: [0, 0, 5])))        // a Box<Enemy> becomes a Box<any Damageable>, allocated once
targets.append(Box(Crate(pos: [4, 0, 2])))
for t in &targets { t.value.takeDamage(10) }       // dynamic dispatch, on each target in place
```

**Both costs show in the type.** `any` marks the dynamic dispatch, and `Box` the allocation, since `any P` never allocates on its own.

**A `Box<any P>` takes only an unscoped value.** The box isn't scoped, so it can go anywhere, and a value that borrows, such as a `Span`, could then outlive what it borrows ([Views](04-views.md)).

## Reference counting: `Shared`

```swift
struct Texture(var pixels: List<UInt8>, var width: Int)              // Frozen: derived by the compiler
struct Material(var albedo: Shared<Texture>, var roughness: Float)   // Frozen too, since Shared<Texture> is

let rock = Shared(Texture(pixels: loadPixels("rock.tex"), width: 512))
let wet = Shared(Material(albedo: rock.share(), roughness: 0.2))     // share() adds an owner, visibly
let dry = Shared(Material(albedo: consume rock, roughness: 0.9))     // a move: the count stays at two
print(wet.value.roughness)                                           // 'value' lends the material read-only
```

**`Shared<T>` lets several owners, on any threads, hold one value, and the last owner to let go destroys it** ([06](../spec/06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)). This is **reference counting**, and the count is atomic.

**Many threads may read a shared value at once, so its type must be one of two kinds:**

- **`Frozen`**: nothing changes it through a shared borrow ([06](../spec/06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)). The compiler derives `Frozen` for a type that holds no `Synchronized` value, object owner, raw pointer or `Closure`. std's containers, such as `List`, are `Frozen` when their elements are.
- **`Synchronized`**: it changes only through its own synchronization, such as a `Mutex`'s lock ([Concurrency](07-concurrency.md#shared-mutable-state)).

**Counting is visible.** `Shared` is move-only. You add an owner with `s.share()`, and a move leaves the count as it is.

**`s.value` lends the value read-only**, for as long as `s` is borrowed.

**The last owner destroys the value at once**, on the thread that drops it. Its `deinit` runs and its memory is freed right there, with no collector to run later.

**A `Frozen` value can't form a cycle**, since nothing in it can change to point back at it. A `Synchronized` value can: a `Shared<Mutex<Node>>` can come to hold an owner of itself, and that cycle leaks.

### Weak links and `LocalShared`

```swift
let grass = Shared(Texture(pixels: loadPixels("grass.tex"), width: 256))
let cached = grass.weak()                            // WeakShared<Texture>: owns nothing
if let tex = cached.upgrade() { draw(tex.value) }    // an owner while 'tex' lives, or nil if the texture is gone
```

**A weak link names a shared value without keeping it alive.** `s.weak()` returns one, a `WeakShared<T>`: 8 bytes, and copyable ([06](../spec/06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)).

**`w.upgrade()` gives you a new owner, a `Shared<T>?`**, which is `nil` once the value is destroyed.

**`LocalShared<T>` keeps a plain count, for owners on one thread.** It takes only a `Frozen` `T`, and hands out no weak links. It never crosses to another thread, so its count needs no atomic operation.

**`Shared<T>` crosses threads when its `T` is `Sendable`**: when values of `T` may move to another thread ([Concurrency](07-concurrency.md#what-may-cross-threads-sendable)).

## Long-lived views: `Slice`

```swift
struct MeshComponent(var vertices: Slice<Vertex>)     // a stored view: a weak link to the buffer, and a range

let package = Shared(try Blob.load("level3.pak"))     // the level's bytes, loaded once
let m = MeshComponent(vertices: try package.slice(of: Vertex.self, at: header.vertexOffset, count: header.vertexCount))
upload(m.vertices.read()!)                            // a Span<Vertex>: one check, then none per element
```

**Long-lived state can't hold a `Span`, so a stored view into a buffer is a `Slice<T>`** ([06](../spec/06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)).

**A slice's buffer lives behind a `Shared`**, often as a `Blob`: a block of bytes of fixed size.

**A slice is copyable, and keeps nothing alive.** It holds a weak link to its buffer.

**`s.read()` checks the buffer, and returns a `Span<T>?`.** It's `nil` once the buffer is gone: its `Shared` value destroyed, or its storage stale after a reset. Reading through the span checks nothing more.

**`slice(of:at:count:)` throws unless the range is in bounds and aligned for `T`.** `T` must be `Pod`: a type for which any bytes are a valid value ([04](../spec/04-types/data-layout.md#plain-data-pod-and-bit-casts)).

**A buffer that changes sits under an `RwLock`**, a lock that lets in many readers or one writer ([Concurrency](07-concurrency.md#locks-mutex-and-rwlock)). A slice of it can also write, through `s.lock()`.

## When allocation fails

**An allocating operation panics when its allocator can't make the allocation** ([06](../spec/06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)). `Box(v)`, `Shared(v)` and `UniquePointer(v)` are among them, so no code goes on with memory it didn't get.

**Each also has a fallible form, for code that can make room and try again.** It throws `AllocError`, the prelude's error for an allocation that failed:

```swift
func spawnBoss(at pos: Vec3) throws(AllocError) -> Box<Enemy> {
    do {
        return try Box.tryNew(Enemy(pos: copy pos, hp: 5000))   // throws AllocError instead of panicking
    } catch {
        evictUnusedAssets()                                      // make room, then try once more
        return try Box.tryNew(Enemy(pos: copy pos, hp: 5000))   // 'pos' is borrowed, so each attempt copies it
    }
}
```

**The fallible forms include:**

- `try Box.tryNew(v)`, `try Shared.tryNew(v)`, `try LocalShared.tryNew(v)` and `try UniquePointer.tryNew(v)`;
- `try Closure.tryNew { … }`, for a closure whose captures don't fit inline;
- the builtin `SoA`'s growing operations, such as `try rows.tryAppend(x)`;
- `allocateRaw` and `reallocateRaw`, which return `nil`, for a collection of your own over raw memory ([10](../spec/10-errors-and-safety/unsafe-code.md#raw-allocations)).

So a collection that must back off under a hard memory limit, such as a streaming loader's, grows through one of these.

**`@noalloc` rules allocation out.** In a function marked `@noalloc`, such as an audio callback, any call that may allocate is a compile error:

```swift
@noalloc
func fillSilence(_ out: mutable MutableSpan<Float>, _ history: mutable List<Float>) {
    for i in 0..<out.count { out[i] = 0 }        // fine: nothing here allocates
    history.append(0)                            // error: 'append' may allocate, and 'fillSilence' is @noalloc
}
```

## In the spec

- [06 Memory and allocators](../spec/06-memory-and-allocators.md): allocator ids and kinds, the current allocator, and the static allocator of read-only data.
- [06 What a reset does](../spec/06-memory-and-allocators/arena-safety.md#what-a-reset-does): every case in which a reset panics, how it orders with other threads, and the `deinit`s it runs.
- [06 Opening an owning value](../spec/06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it): what counts as an open, and how opens race with resets.
- [06 Allocators over other allocators](../spec/06-memory-and-allocators/allocator-implementations.md#allocators-over-other-allocators): budgets and other wrappers, and allocators with a backing.
- [06 Writing an allocator](../spec/06-memory-and-allocators/allocator-implementations.md#writing-an-allocator-allocatorimpl): `AllocatorImpl` and what conforming to it promises.
- [06 Owning boxes](../spec/06-memory-and-allocators/owning-values.md#owning-boxes): `Box`, `Shared`, `LocalShared` and weak links in full, `Frozen`, and handing an owner to C.
- [06 Long-lived views](../spec/06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers): slices of a locked `Blob` or `List`, and what making one checks.
- [06 Allocation failure](../spec/06-memory-and-allocators/allocation-lifecycle.md#allocation-failure): every fallible form, and what `@noalloc` rejects.
- [06 `TrivialFree`](../spec/06-memory-and-allocators/allocation-lifecycle.md#releasing-a-value-without-destroying-it-trivialfree): forgetting a value in an arena with `release`, instead of destroying it.
- [05 `any P`](../spec/05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch): existentials, `Box<any P>`, and passing one to generic code.
- [03 Objects in arenas](../spec/03-handles-and-objects.md#objects-in-arenas-and-other-allocators): objects that a reset or an unregistration destroys.
