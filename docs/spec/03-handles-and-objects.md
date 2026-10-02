# 03 · Handles and objects

## Pools and handles

A link to a value in a collection can be a **handle**: a small index into a pool, checked at each use, which can go stale but never dangle.

```swift
var enemies = Pool<Enemy>(capacity: 4096)
let h = enemies.insert(Enemy(pos: spawn, hp: 100))   // h: Handle<Enemy>, 8 bytes, copyable
squad.members.append(copy h)                         // store copies anywhere

enemies[h]?.hp -= 10                                 // nil, and skipped, if the enemy is gone
enemies.remove(h)                                    // every copy of h goes stale at once
if enemies[h] == nil { … }                           // true: a stale handle reads nil
```

The standard library declares `Handle` this way, and `pool[h]` is an optional projection ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)):

```swift
@align(8) public struct Handle<T> private init(public let index: UInt32, public let generation: UInt32): Copyable, Hashable {
    public var bits: UInt64 { … }             // its 8 bytes as one UInt64, for C to hold
    public init?(bits: UInt64) { … }          // nil only for generation 0
}
```

**`Handle` is 8-aligned, so C holds it as a `uint64_t`** ([08](08-c-interop.md#c-representations)). `Handle<T>?` is 8 bytes too, since its `nil` is all zero bits, which no handle has: a handle's generation is never 0 ([04](04-types.md#optionals)). Its primary initializer is private, so it isn't `Pod` ([04](04-types.md#plain-data-pod-and-bit-casts)), and other modules build one only through `init?(bits:)`.

- **A `Pool<T>`** stores its elements densely. `pool[h]` is `nil` once the element is removed, and stays `nil`: a slot whose generation would wrap is abandoned, never reused, so a handle never names a later element. Removal makes every copy of the handle stale at once, and may move the last element into the hole. A forged handle reads `nil` or some live element of that pool.
- **A `StablePool<T>`** abandons slots the same way, and never moves an element, so a pool element has a stable address there, and `stablePool.pin(h)` can hand it to C ([below](#pinning-for-c)). Its `T` is `~Scoped` ([02](02-views-and-dependencies.md#generic-code-and-scoped)), since an unscoped pin keeps an element, and its `deinit`, waiting past every scope.

## Objects and weak pointers: `UniquePointer<T>` and `WeakPointer<T>`

A `UniquePointer` owns one value, its **object**, in memory from any allocator, and any number of `WeakPointer`s point at it, as a node points at its parent:

```swift
var renderer = UniquePointer(Renderer(device: dev))   // the one owner, move-only
let r: WeakPointer<Renderer> = renderer.weak()        // copyable: store any number, cycles included

struct Sprite(var mesh: MeshId, var renderer: WeakPointer<Renderer>)
struct Node(var parent: WeakPointer<Node>?, var children: List<UniquePointer<Node>>)     // tree with parent pointers

renderer.value.beginFrame()                    // through the owner: the object itself, no optional
r.value?.submit(mesh)                          // optional projection: nil once the object is destroyed
if var rd = &r.value { rd.beginFrame(); rd.submit(mesh) }
r.value!.stats.drawCalls += 1                  // '!' panics if the object is gone
```

- **A weak pointer's `value` is a `T?` projection.** It reads `nil` once the object is destroyed, so a weak pointer never dangles. Comparing it with `nil` checks only that the object lives, and takes no mark ([below](#dynamic-exclusivity)), so it never conflicts. The owner keeps the object alive, so `renderer.value` projects a `T`. It fails only when something else, such as an arena reset, has destroyed the object, and the access then panics ([below](#destroying-an-object)).
- **A weak pointer never aliases a mutation.** Two weak pointers to one object are aliases the static checker can't see, so each use is checked at run time ([below](#dynamic-exclusivity)).
- **They stay on one thread.** `UniquePointer` and `WeakPointer` aren't `Sendable` ([07](07-concurrency.md#what-may-cross-threads-sendable)), so no value holding one moves to or is lent to another thread. Each object stays on the thread that made it, its **home thread**, so the object is **thread-bound**. Its access marks never synchronize with another thread. It is destroyed only on its home thread: a reset or an unregistration on another thread panics instead ([below](#objects-in-arenas-and-other-allocators)).
- **A home thread's identity is never given to another thread**, not even to one that C starts after the home thread exits without detaching. So the home thread's objects are then reached from no thread, and leak: `WeakPointer(bits:)` and `adopt` read `nil` for them ([07](07-concurrency.md#global-state)).
- **Owners and weak pointers are 8 bytes and 8-aligned.** Their `nil` is all zero bits, so `UniquePointer<T>?` and `WeakPointer<T>?` are 8 bytes too, and a weak pointer's bits fit a C `uint64_t` ([below](#weak-pointers-as-bits-and-handing-objects-to-c)).

### Dynamic exclusivity

Every access to an object's value, through the owner or any weak pointer, is checked:

- **Marks.** A **read access** is any shared use of the value, such as a `read` projection, a `let` binding or a borrowing method call, and holds a shared mark. A **modify access** is any change, such as a `modify` projection, a `var` binding of `&place` or a `mutating` call, and holds an exclusive mark. Each mark lasts until the last use of every value that depends on the access (rule 6 in [02](02-views-and-dependencies.md#rule-6-dynamic-accesses)).
- **Conflicts.** A conflicting access panics before it touches the value. So an observer that calls back into the object that is notifying it panics when either access changes the object: the observer's or the notifying method's. Destroying the object while any access to it is live panics too ([below](#destroying-an-object)).
- **Counts never wrap.** An access that would take the reader count past its limit panics, in every build, as every count kept for safety does ([10](10-errors-and-safety.md#what-panics)). So does creating an object when no generation is left ([below](#destroying-an-object)).

### Sharing across threads

**Objects stay on their home thread.** Data that several threads use lives behind a reference-counted pointer, a `Shared<T>`, whose value is `Frozen` or `Synchronized`, such as a `Mutex`. A `WeakShared<T>` links to it without keeping it alive ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)):

```swift
let mixer = Shared(Mutex(AudioMixer()))                    // AudioMixer must be Sendable
let m: WeakShared<Mutex<AudioMixer>> = mixer.weak()        // copyable and Sendable: may go to any thread

Thread.start { [copy m, copy clip] in
    if let mx = m.upgrade() { mx.value.lock { $0.play(clip) } }   // one more owner of the mixer for as long as 'mx' lives
}
```

### Destroying an object

```swift
extension Node {
    mutating func prune() { parent!.value!.children.removeAll() }   // destroys this node too, with its siblings
}
var root = UniquePointer(Node(parent: nil, children: List()))
root.value.children.append(UniquePointer(Node(parent: root.weak(), children: List())))
let leaf = root.value.children[0].weak()

leaf.value!.prune()                  // panics: the node is destroyed while 'prune' still accesses it
root.value.children.removeAll()      // instead: no access to a child is live, so each deinit runs here
```

**Destroying an object runs its `deinit` at once, on its home thread, and panics while an access to it is live.** Dropping or overwriting the owner destroys the object. So do resetting or unregistering the allocator its value came from ([below](#objects-in-arenas-and-other-allocators)), and its home thread's end. From then every weak pointer reads `nil` and no new access can begin.

- **The `deinit` runs once, before the destruction returns.** It never runs again, even when another `deinit` drops an owner of the same object. Its memory is freed when it returns.
- **A live access panics the destruction**, through the owner or any weak pointer, in every build, since the `deinit` would otherwise run under code still using the value. So an object that ends itself leaves the removal to its owner's code after the access ends, as a tree that drains a list of nodes to prune does.
- **A pin keeps the `deinit` waiting.** Destroying a pinned object makes every weak pointer read `nil` at once, and the drop of its last pin runs the `deinit` and frees the memory ([below](#pinning-for-c)).
- **Owners go stale too.** That happens when something else, such as an arena reset or an unregistration, destroys their object. An access through a stale owner panics, and so does pinning through it. Dropping it does nothing: its object's `deinit` has already run.
- **A thread's objects end with it.** Every thread-bound object belongs to its home thread wherever its owner lies, even in a stale container or in C. So the thread's teardown ([07](07-concurrency.md#global-state)) destroys its objects on it, those it leaked to C included ([below](#weak-pointers-as-bits-and-handing-objects-to-c)). Their `deinit`s run then, except the `deinit` of an object that a never-dropped pin still holds ([below](#pinning-for-c)).
- **A weak pointer never names a later object.** It names its object by a **generation** that no other object of the run gets. So however many objects are created and destroyed, a weak pointer to a destroyed object reads `nil` forever.

### Objects in arenas and other allocators

**`UniquePointer(value, allocator: a)` takes any allocator.** Objects in an arena die together when it is reset ([06](06-memory-and-allocators.md)), and objects in a heap when it is unregistered. Afterwards every weak pointer to them reads `nil`, and their owners are stale ([above](#destroying-an-object)).

- **Their `deinit`s run inside the reset or the unregistration**, on its thread, for every object whose value its memory holds, including through a wrapper over the allocator.
- **So it checks them first.** It panics, before destroying any, when one of them has a live access, a pin, or another home thread, whose `deinit` must run on that thread ([06](06-memory-and-allocators.md#what-a-reset-does)). An arena that several threads make objects in is reset only after every other thread has destroyed its objects there.
- **Creation racing a reset or an unregistration on another thread is ordered either before it or after it.** Ordered before, the reset or unregistration panics, since the new object's home thread is another. Ordered after, the object survives a reset, and its allocation through an unregistered allocator panics ([06](06-memory-and-allocators.md#unregistering-an-allocator)).

### Weak pointers as bits, and handing objects to C

- **Weak pointers from bits are checked.** `w.bits` packs a weak pointer into a `UInt64`. `WeakPointer<T>(bits:)` returns `nil` unless the bits name a live object of type `T` whose home thread is the calling thread. It is memory-safe for any bits, even while another thread destroys the object. Genuine bits never resolve to an object other than the one they were made for. Forged or mistyped bits, like a forged `Handle`, read `nil` or name some live `T` on this thread.
- **Existential weak pointers from bits.** `WeakPointer<any P>(bits:)` takes the same 64 bits, and reads `nil` unless the object's type conforms to `P` ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).

**`UniquePointer.leak(p)` hands ownership to C.** It gives up the owner and returns a weak pointer for C to hold as a `uint64_t`. A leaked object is used through its weak pointers as any other, and stays leaked until one of these:

- `UniquePointer.adopt(w)` returns its owner;
- a reset or an unregistration of its allocator destroys it ([above](#objects-in-arenas-and-other-allocators));
- its home thread tears down ([above](#destroying-an-object)).

**`adopt` returns `nil` unless `w` names a live leaked object of type `T` whose home thread is the caller's.** A successful `adopt` ends the leak. So a forged, mistyped or repeated `adopt` is harmless, and so is one of an object never leaked. A `Shared` value crosses to C the same way ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)).

### Pinning for C

**While a pin lives, the address it holds is safe for C to use.** `stablePool.pin(h)` returns a move-only, unscoped **`Pin<T>?`**, which is `nil` for a stale handle. `p.pin()` on an object's owner returns a **`LocalPin<T>`**, which works the same way but never leaves its object's home thread. A dense `Pool` can't pin, since removals move its elements. Pinning takes a shared `self`, so several threads may pin at once.

**A pin keeps its memory alive, independent of any owner.** While it lives:

- **The address is stable and valid.** It is `pin.address`, an `unsafe` field of type `*T`, so safe code never sees an address it could compare later.
- **Its memory is never freed or reused.** Each of these leaves the release or reuse waiting for the last pin:
  - destroying the object;
  - destroying or clearing the `StablePool`, `pool = StablePool()` included;
  - a `StablePool` removal that would reuse the slot.

  Resetting an arena or unregistering an allocator that the memory came from panics instead of waiting ([06](06-memory-and-allocators.md#what-a-reset-does)). Each pin's drop happens before the `deinit`, release or reuse that waited for it, in the memory model's order ([07](07-concurrency.md#atomics-and-locks)). So what a thread did through the address before the drop is done by then.
- **`deinit` waits for the last pin, whose drop runs it.** So C never reads a destroyed value. Destroying a pinned object makes every weak pointer read `nil` at once, and the thread that drops the last pin runs the `deinit` and frees the memory. `stablePool.remove(h)` on a pinned element does the same, and `stablePool.take(h)`, which moves the element out, returns `nil`. A pin that is never dropped, such as one in a stale container, keeps the `deinit` and the free from running ([06](06-memory-and-allocators.md#stale-values-and-the-deinits-a-reset-runs)).
- **The last pin drops on a thread the value may be destroyed on.** `Pin<T>` is `Sendable` when `T` is, since pin counts are atomic, and a `LocalPin<T>` never is, so it drops on its object's home thread. A value that isn't `Sendable`, such as a `StablePool` element holding a `UniquePointer` or an OpenGL object, is pinned only on its own thread, and its pins stay there.

**A pin guarantees memory, not immutability.** Rayo code can still mutate a pinned value, or assign it a new one. The old value's `deinit` then runs at once, and C sees the new value at the same address. The pin covers the value's own memory, not the buffers it owns, which such a write may reallocate or free.
