# 6 · Memory and allocators

Your game uses memory at two speeds. The level's props, meshes and names live until the level unloads. Each frame's scratch data, such as the list of meshes the camera sees, lives for one frame. An arena suits the scratch: it frees nothing one value at a time, and frees everything it handed out in one step.

```swift
import std.memory                                            // Arena

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

In C++, a pointer that survives into the next frame is a silent use-after-free: the arena hands its memory out again, and the old pointer reads whatever is there now. Rayo keeps the arena and its one-step free, and turns that bug into a panic at the line that would read reused memory. This chapter shows where memory comes from, how arenas stay safe, and the types that own one value in an allocation of its own: `Box` and the reference-counted `Shared`.

## Allocators are values

**An `Allocator` is a copyable id that names a registered allocator** ([06](../spec/06-memory-and-allocators.md#allocator-values)). `Allocator.register` takes an allocator implementation, such as an `Arena`, and returns its id. `.system`, the platform's general-purpose heap, is always registered.

```swift
var levelProps = List<Prop>(allocator: levelHeap)    // grows and frees through levelHeap, for its whole life
var editorProps = List<Prop>(allocator: .system)     // the same type: List<Prop>
var names = List<String>()                           // no allocator given: the current one (below)
```

**Every owning value records the allocator its storage came from.** An **owning value** is one that owns storage from an allocator, such as a `List`, a `String` or a `Box` ([06](../spec/06-memory-and-allocators.md#how-values-record-their-allocator)). It grows and frees through that allocator, so the allocator isn't part of its type. A function that takes a `List<Prop>` takes both lists above.

**Every registered allocator is one of three kinds** ([06](../spec/06-memory-and-allocators.md#allocator-values)):

- A **heap**, such as `.system` or a TLSF heap, frees each allocation on its own.
- An **arena** frees nothing on its own. Freeing into it does nothing, and a **reset** frees everything it handed out at once.
- A **wrapper**, such as a memory budget, passes another allocator's allocations through and keeps accounts of them ([06](../spec/06-memory-and-allocators.md#allocators-over-other-allocators)).

An allocator other than `.system` is library code that implements the `AllocatorImpl` protocol, so you can write your own ([06](../spec/06-memory-and-allocators.md#writing-an-allocator-allocatorimpl)). Conforming is an `unsafe` promise to keep that protocol's contract, since the compiler can't check an allocator's bookkeeping ([06](../spec/06-memory-and-allocators.md#what-conforming-promises)). Every registered allocator must be safe to call from any thread.

## The current allocator

**Every thread has a current allocator, which starts as `.system`.** `using allocator = a { … }` makes `a` current for the block, and restores the one before when the block exits, by an early return too ([06](../spec/06-memory-and-allocators.md#the-current-allocator)).

Only a few things read the current allocator, and each records it in what it builds:

- a constructor of an allocating type that isn't given an allocator, such as `List<Enemy>()`, `String("wave \(n)")` or `Box(e)`;
- `clone()`, which builds its copy there;
- a list literal, as in `let ys: List<_> = [1, 2]`;
- a closure converted into a `Closure` whose captures don't fit inline ([05](../spec/05-protocols-generics-and-closures.md#unscoped-closures-closuref)).

An empty `List<Enemy>()` allocates nothing yet. It records the allocator, and grows there later.

**A collection keeps its allocator for life.** It grows through the allocator it was built with, wherever the code that grows it runs. That makes a block's reach easy to misjudge:

```swift
var names = List<String>()                       // built outside the block: its buffer is in .system
using allocator = frameArena {
    names.append(String("wave \(wave)"))         // the list grows in .system, but the new String is in the arena
}
frameArena.reset()
print(names[0])                                  // panics: the string came from 'frameArena' before its reset
```

**The current allocator belongs to the thread.** What lent work builds on another thread with no allocator given comes from that thread's current allocator, not yours ([07](../spec/07-concurrency.md#thread-locals-in-lent-work)). Chapter 7 covers lent work ([Concurrency](07-concurrency.md)).

## Arenas and resets

**`arena.reset()` frees everything the arena handed out, at once, after checking that nothing still uses it** ([06](../spec/06-memory-and-allocators.md#what-a-reset-does)). It costs the same however many values the arena holds, plus one `deinit` for each object in it that has one. Every value allocated from the arena before the reset is **stale** from then on. Every value allocated after it is valid.

Two checks keep a reset from becoming a use-after-free:

- **Opening a stale value panics**, instead of reading memory the arena has handed out again.
- **A reset panics while anything still uses the arena's memory**, on any thread. It never waits.

```swift
var hits = List<Vec3>(allocator: frameArena)
hits.append(.zero)

let pts = hits.span         // a view into the arena's memory: a use of the arena while 'pts' is live
frameArena.reset()          // panics: 'pts' is used below
print(pts[0])
```

```swift
print(hits[0])              // this use of the arena ends with its statement
frameArena.reset()          // fine: nothing uses the arena, and its memory is freed
hits.append(.zero)          // panics: 'hits' was allocated in 'frameArena' before its reset
```

So finish with what the arena holds before you reset it, and copy out what must outlive it ([below](#keeping-results-past-a-reset)). Reset an arena that worker threads use only after their jobs finish, as a game's main loop does once per frame: a reset while a job still reads the arena panics.

### What an open checks

An **open** is any access that reaches the storage an owning value owns ([06](../spec/06-memory-and-allocators.md#opening-an-owning-value-checks-it)):

- reading what it holds, such as an element or a `Box`'s value;
- taking a span of it;
- iterating it;
- growing it.

**Every owning value carries an allocator word**: 8 bytes that name its allocator, and date its storage against that allocator's resets ([06](../spec/06-memory-and-allocators.md#how-values-record-their-allocator)). Each open checks the word, so an open of a stale value panics. This is a memory-safety check, on in every build, like a bounds check.

**An open also counts as a use of its allocator, for as long as what it lends is live.** That is how `reset()` knows that `pts` still reads the arena: the span came from an open of `hits`, which lasts until the span's last use. Each thread keeps its own counts, so counting writes nothing another thread writes. Storage from `.system` is never reset, so its opens count nothing.

### Stale values, objects and heaps

- **Destroying a stale value does nothing.** It skips the free, and its elements' `deinit`s, so whatever those elements owned outside the arena leaks. So a value in an arena should own nothing outside it.
- **A reset destroys the arena's objects.** An object made with `UniquePointer(value, allocator: frameArena)` dies in the reset, which runs its `deinit` on the resetting thread. Inside that `deinit`, the object can still read what it owns from the arena ([06](../spec/06-memory-and-allocators.md#stale-values-and-the-deinits-a-reset-runs)). Its weak pointers read `nil` from then on. The reset panics first when one of these objects has a live access, a pin or another home thread ([03](../spec/03-handles-and-objects.md#objects-in-arenas-and-other-allocators)).
- **Only an arena resets.** `reset()` on a heap, `.system` included, panics.

**A heap ends with `Allocator.unregister`.** When the level unloads, `Allocator.unregister(levelHeap)` checks for uses as a reset does. Then every value still allocated from the heap goes stale, and its objects are destroyed ([06](../spec/06-memory-and-allocators.md#unregistering-an-allocator)). The id stays invalid for good, so nothing made from it ever passes its check again.

## Keeping results past a reset

**To keep a value past a reset, build it in an allocator that outlives the reset.** `clone()` builds its copy in the current allocator, so a `using allocator = .system` block inside the arena's block copies a value out:

```swift
using allocator = frameArena {
    var names = List<String>()
    collectNames(world, into: &names)                             // the list and its strings come from the arena
    using allocator = .system { world.results = names.clone() }   // the clone and its strings come from .system
}
frameArena.reset()
world.results.append(String("late"))                              // fine: nothing in it came from the arena
```

## One owned value: `Box`

**`Box<T>` owns one value in an allocation of its own** ([06](../spec/06-memory-and-allocators.md#owning-boxes)). It is move-only, and destroying it destroys its value and frees its memory. `box.value` reaches the value in place.

```swift
var boss = Box(Enemy(pos: [0, 0, 40], hp: 5000))   // one allocation, from the current allocator
boss.value.takeDamage(250)                          // changes the enemy in place
```

**A recursive type goes through a `Box`.** A value never contains itself, so a tree holds its children through owners, and the allocation shows in the type ([04](../spec/04-types.md#structs)):

```swift
enum Tree {
    case leaf(Int)
    case node(Box<Tree>, Box<Tree>)
}
```

### Boxes of `any P`

**`Box<any P>` owns a value whose type is known only at run time** ([05](../spec/05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)). An **existential**, `any P`, holds a value of any type that conforms to the protocol `P`, and calls `P`'s requirements through a table. A plain `any P` only borrows its value, like a view. To own one, put it in a box. With chapter 1's `Damageable`, which `Enemy` conforms to ([Basics](01-basics.md#protocols-and-generics)):

```swift
struct Crate(var pos: Vec3, var hp: Float = 20)
extension Crate: Damageable {
    mutating func takeDamage(_ amount: Float) { hp -= amount }
}

var targets = List<Box<any Damageable>>()
targets.append(Box(Enemy(pos: [0, 0, 5])))        // a Box<Enemy> becomes a Box<any Damageable>, allocated once
targets.append(Box(Crate(pos: [4, 0, 2])))
for var t in &targets { t.value.takeDamage(10) }   // dynamic dispatch, on each target in place
```

The dynamic dispatch and the heap allocation both show in the type, since `any P` never allocates on its own. A box of `any P` forgets its value's type, and with it what the value borrows, so it takes no scoped value, such as a `Span`.

## Reference counting: `Shared`

**`Shared<T>` lets several owners, on any threads, hold one value, and the last owner to let go destroys it** ([06](../spec/06-memory-and-allocators.md#sharedt-data-with-many-owners)). This is **reference counting**, with an atomic count. Since many threads may read the value at once, it must be one of these:

- **`Frozen`**, so nothing changes it through a shared borrow. The compiler derives `Frozen` for a type that holds no `Synchronized` value, object owner, raw pointer or `Closure`. std's containers, such as `List`, are `Frozen` when their elements are ([06](../spec/06-memory-and-allocators.md#frozen-types-with-no-interior-mutability)).
- **`Synchronized`**, so it changes only through its own synchronization, as a `Mutex` does ([Concurrency](07-concurrency.md#shared-mutable-state)).

```swift
struct Texture(var pixels: List<UInt8>, var width: Int)              // Frozen: derived by the compiler
struct Material(var albedo: Shared<Texture>, var roughness: Float)   // Frozen too, since Shared<Texture> is

let rock = Shared(Texture(pixels: loadPixels("rock.tex"), width: 512))
let wet = Shared(Material(albedo: rock.share(), roughness: 0.2))     // share() adds an owner, visibly
let dry = Shared(Material(albedo: consume rock, roughness: 0.9))     // a move: the count stays at two
print(wet.value.roughness)                                           // 'value' lends the material read-only
```

- **Counting is visible.** `Shared` is move-only. Each new owner takes an explicit `s.share()`, and a move leaves the count as it is.
- **`s.value` lends the value read-only**, for as long as `s` is borrowed.
- **The last owner destroys the value at once**, on the thread that drops it. Its `deinit` runs and its memory is freed there, with no collector running later.
- **A `Frozen` value can't form a cycle**, since nothing in it can change to point back at it. A `Synchronized` one can, as a `Shared<Mutex<Node>>` that holds an owner of itself does, and that cycle leaks.

### Weak links and `LocalShared`

**A weak link names a shared value without keeping it alive.** `s.weak()` returns a **weak link**, a `WeakShared<T>`: 8 bytes and copyable ([06](../spec/06-memory-and-allocators.md#sharedt-data-with-many-owners)). `w.upgrade()` returns a new owner, a `Shared<T>?`, which is `nil` once the value is destroyed:

```swift
let grass = Shared(Texture(pixels: loadPixels("grass.tex"), width: 256))
let cached = grass.weak()                            // WeakShared<Texture>: owns nothing
if let tex = cached.upgrade() { draw(tex.value) }    // an owner while 'tex' lives, or nil if the texture is gone
```

**`LocalShared<T>` keeps a plain count, for owners on one thread.** It takes a `Frozen` `T` only and hands out no weak links. It never crosses to another thread, so its count needs no atomic operation. `Shared<T>` crosses threads when its `T` is `Sendable` ([Concurrency](07-concurrency.md#what-may-cross-threads-sendable)).

## Long-lived views: `Slice`

**A `Span` can't be stored in long-lived state, so a stored view into a buffer is a `Slice<T>`** ([06](../spec/06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)). Its buffer lives behind a `Shared`, often as a `Blob`, a block of bytes of fixed size:

```swift
struct MeshComponent(var vertices: Slice<Vertex>)     // a stored view: a weak link to the buffer, and a range

let package = Shared(try Blob.load("level3.pak"))     // the level's bytes, loaded once
let m = MeshComponent(vertices: try package.slice(of: Vertex.self, at: header.vertexOffset, count: header.vertexCount))
upload(m.vertices.read()!)                            // a Span<Vertex>: one check, then none per element
```

A **slice** is copyable, and keeps nothing alive. `s.read()` returns a `Span<T>?`, which is `nil` once the buffer is gone: its `Shared` value destroyed, or its storage stale after a reset. `slice(of:at:count:)` throws unless the range is in bounds and aligned for `T`, which must be `Pod`, a type for which any bytes are a valid value. A buffer that changes sits under an `RwLock` ([Concurrency](07-concurrency.md#locks-mutex-and-rwlock)), and a slice of it can also write through `s.lock()`.

## When allocation fails

**`Box(v)`, `Shared(v)` and `UniquePointer(v)` panic when their allocator can't make the allocation**, as the language's other allocating operations do ([06](../spec/06-memory-and-allocators.md#allocation-failure)). Each has a fallible `tryNew` form, which throws `AllocError`, the prelude's error for an allocation that failed:

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

The fallible forms include:

- `try Box.tryNew(v)`, `try Shared.tryNew(v)`, `try LocalShared.tryNew(v)` and `try UniquePointer.tryNew(v)`;
- `try Closure.tryNew { … }`, for a closure whose captures don't fit inline;
- the builtin `SoA`'s growing operations, such as `try rows.tryAppend(x)`;
- `allocateRaw` and `reallocateRaw`, which return `nil`, for a collection of your own over raw memory ([10](../spec/10-errors-and-safety.md#raw-allocations)).

So a collection that must back off under a hard memory limit, as a streaming loader's does, grows through one of these.

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
- [06 What a reset does](../spec/06-memory-and-allocators.md#what-a-reset-does): every case in which a reset panics, how it orders with other threads, and the `deinit`s it runs.
- [06 Opening an owning value](../spec/06-memory-and-allocators.md#opening-an-owning-value-checks-it): what counts as an open, and how opens race with resets.
- [06 Allocators over other allocators](../spec/06-memory-and-allocators.md#allocators-over-other-allocators): budgets and other wrappers, and allocators with a backing.
- [06 Writing an allocator](../spec/06-memory-and-allocators.md#writing-an-allocator-allocatorimpl): `AllocatorImpl` and what conforming to it promises.
- [06 Owning boxes](../spec/06-memory-and-allocators.md#owning-boxes): `Box`, `Shared`, `LocalShared` and weak links in full, `Frozen`, and handing an owner to C.
- [06 Long-lived views](../spec/06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers): slices of a locked `Blob` or `List`, and what making one checks.
- [06 Allocation failure](../spec/06-memory-and-allocators.md#allocation-failure): every fallible form, and what `@noalloc` rejects.
- [06 `TrivialFree`](../spec/06-memory-and-allocators.md#releasing-a-value-without-destroying-it-trivialfree): forgetting a value in an arena with `release`, instead of destroying it.
- [05 `any P`](../spec/05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch): existentials, `Box<any P>`, and passing one to generic code.
- [03 Objects in arenas](../spec/03-handles-and-objects.md#objects-in-arenas-and-other-allocators): objects that a reset or an unregistration destroys.
