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

std declares `Handle` as follows; `pool[h]` is an optional projection ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)):

```swift
@align(8) public struct Handle<T> private init(public let index: UInt32, public let generation: UInt32): Copyable, Hashable {
    public var bits: UInt64 { … }             // its 8 bytes as one UInt64, for C to hold
    public init?(bits: UInt64) { … }          // nil only for generation 0
}
```

`Handle` is 8-aligned, so C holds it as a `uint64_t` ([09](09-c-interop.md#c-representations)), and `Handle<T>?` is 8 bytes too, since its `nil` is all zero bits, which no handle has, as its generation is never 0 ([04](04-types.md#optionals)). Its primary initializer is private, so it isn't `Pod` ([04](04-types.md#plain-data-pod-and-bit-casts)), and other modules build one only through `init?(bits:)`.

- **A `Pool<T>`** stores its elements densely. `pool[h]` is `nil` once the element is removed, and stays `nil`: a slot whose generation would wrap is abandoned, never reused, so a handle never names a later element. Removal makes every copy of the handle stale at once, and may move the last element into the hole. A forged handle reads `nil` or some live element of that pool.
- **A `StablePool<T>`** abandons slots the same way, and never moves an element, so a pool element has a stable address there, and `stablePool.pin(h)` can hand it to C ([below](#pinning-for-c)). Its `T` is `~Scoped` ([02](02-views-and-dependencies.md#scoped-values)), since an unscoped pin keeps an element, and its `deinit`, waiting past every scope.

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

- **A weak pointer's `value` is a `T?` projection.** It reads `nil` once the object is destroyed, so a weak pointer never dangles. Comparing it with `nil` checks only that the object lives, and takes no mark ([below](#dynamic-exclusivity)), so it never conflicts. The owner keeps the object alive, so `renderer.value` projects a `T`, and fails only when something else, such as an arena reset, has destroyed the object: the access then panics ([below](#destroying-an-object)).
- **A weak pointer never aliases a mutation.** Two weak pointers to one object are aliases the static checker can't see, so each use is checked at run time ([below](#dynamic-exclusivity)).
- **They stay on one thread.** `UniquePointer` and `WeakPointer` aren't `Sendable` ([07](07-concurrency.md#what-may-cross-threads-sendable)), so no value holding one moves to or is lent to another thread, and each object stays on the thread that made it, its **home thread**, so the object is **thread-bound**. Their access marks never synchronize with another thread. A reset or an unregistration on another thread reaches the object's liveness check as it reaches an open ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)), and the object's `deinit` runs on its home thread. A home thread's identity is never given to another thread, not even one C starts after it exits without detaching, so its objects are then reached from no thread: `WeakPointer(bits:)` and `adopt` read `nil` for them, and what was queued to it never runs ([07](07-concurrency.md#global-state)).
- **Owners and weak pointers are 8 bytes and 8-aligned.** Their `nil` is all zero bits, so `UniquePointer<T>?` and `WeakPointer<T>?` are 8 bytes too, and a weak pointer's bits fit a C `uint64_t` ([below](#weak-pointers-as-bits-and-handing-objects-to-c)).

### Dynamic exclusivity

Every access to an object's value, through the owner or any weak pointer, is checked:

- **Marks.** A **read access**, any shared use of the value such as a `read` projection, a `let` binding or a borrowing method call, holds a shared mark, and a **modify access**, any change such as a `modify` projection, a `var` binding of `&place` or a `mutating` call, an exclusive mark, until the last use of every value that depends on it (rule 6 in [02](02-views-and-dependencies.md#dependencies)).
- **Conflicts.** A conflicting access panics before it touches the value. So an observer that calls back into the object that is notifying it panics when either access changes the object: the observer's or the notifying method's. Destruction is not an access and never conflicts: it retires the object's value ([below](#destroying-an-object)).
- **Counts never wrap.** An access that would take the reader count past its limit panics, in every build, as every count kept for safety does ([11](11-errors-and-safety.md#what-panics)), and so does creating an object when no generation is left ([below](#destroying-an-object)).

### Sharing across threads

Objects stay on their home thread. Data that several threads use lives behind a counted owner, `Shared<T>`, whose value is `Frozen` or `Synchronized`, such as a `Mutex`, and a `WeakShared<T>` links to it without keeping it alive ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)):

```swift
let mixer = Shared(Mutex(AudioMixer()))                    // AudioMixer must be Sendable
let m: WeakShared<Mutex<AudioMixer>> = mixer.weak()        // copyable and Sendable: may go to any thread

Thread.start { [copy m, copy clip] in
    if let mx = m.upgrade() { mx.value.lock { $0.play(clip) } }   // a counted owner for as long as 'mx' lives
}
```

### Destroying an object

**Destruction retires the object's value; it never waits for a reader or panics on a live access.** Dropping or overwriting the owner destroys the object, and so does resetting or unregistering the allocator its value came from ([below](#objects-in-arenas-and-other-allocators)). From then every weak pointer reads `nil` and no new access can begin. The value is **retired** ([08](08-grace-periods-and-checkpoints.md#grace-periods-how-deferred-memory-is-reclaimed)): its `deinit` and memory release wait until no reader can still be using it.

- **A retired value's `deinit` runs once, when nothing can still see the value.** Then no access to it is live and no pin holds it ([below](#pinning-for-c)). It starts on whichever path below comes first, and never starts again, even when another `deinit` drops an owner of the same object.
- **A thread-bound object's `deinit` runs on its home thread.** Destroyed through its owner, which is on that thread, its `deinit` runs at once if no access is live and no pin holds it, and otherwise it is queued to the home thread, which runs it at its next outermost section entry ([08](08-grace-periods-and-checkpoints.md#deinits-queued-to-a-thread)), so ending an access or dropping a pin never runs a `deinit` the code didn't ask for. A reset or an unregistration always queues it to the home thread ([below](#objects-in-arenas-and-other-allocators)).
- **A retired value keeps its memory until its `deinit` has finished.** A later reset or unregistration of its allocator doesn't release that memory first. If a reset or unregistration of its allocator comes before its `deinit` runs, whatever retired the object, the `deinit` can still read what the value owns there ([06](06-memory-and-allocators.md#stale-values-and-retired-objects)).
- **Owners go stale too.** That happens when something else, such as an arena reset or an unregistration, destroys their object. An access through a stale owner panics, and so does pinning through it. Dropping it does nothing: its object's `deinit` was already scheduled when the object was destroyed.
- **A thread's objects end with it.** Every thread-bound object belongs to its home thread wherever its owner lies, even in a stale container or in C. So in the thread's teardown ([07](07-concurrency.md#global-state)), its objects are destroyed on it, those it leaked to C included ([below](#weak-pointers-as-bits-and-handing-objects-to-c)), with their `deinit`s, except one that a pin never dropped still holds ([below](#pinning-for-c)).
- **A weak pointer never names a later object.** It names its object by a **generation** that no other object of the run gets, so however many objects are created and destroyed, a weak pointer to a destroyed object reads `nil` forever.

### Objects in arenas and other allocators

`UniquePointer(value, allocator: a)` takes any allocator. Objects in an arena die together when it is reset ([06](06-memory-and-allocators.md)), and objects in a heap when it is unregistered: afterwards every weak pointer to them reads `nil`, and their owners are stale ([above](#destroying-an-object)).

- **Destroying them all is O(1)** in the number of objects: a reset or an unregistration destroys every object whose value its memory holds, including through a wrapper over the allocator.
- **Their `deinit`s run later**, never inside the reset or the unregistration itself: each on its object's home thread, at that thread's next outermost section entry, which may be on the thread that reset. An object still being created is the exception (below).
- **Creation racing a reset or an unregistration** is ordered either before it, and the object is destroyed with the others, or after it: the object survives a reset, and its allocation through an unregistered allocator panics ([06](06-memory-and-allocators.md#unregistering-an-allocator)). An object destroyed this way while it was still being created has its value destroyed at once, on the creating thread, and its creation returns a stale owner.

### Weak pointers as bits, and handing objects to C

- **Weak pointers from bits are checked.** `w.bits` packs a weak pointer into a `UInt64`. `WeakPointer<T>(bits:)` returns `nil` unless the bits name a live object of type `T` whose home thread is the calling thread. It is memory-safe for any bits, even while another thread destroys the object. Genuine bits never resolve to an object other than the one they were made for; forged or mistyped bits, like a forged `Handle`, read `nil` or name some live `T` on this thread.
- **Existential weak pointers from bits.** `WeakPointer<any P>(bits:)` takes the same 64 bits, and reads `nil` unless the object's type conforms to `P` ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).
- **Handing ownership to C.** `UniquePointer.leak(p)` gives up the owner and returns a weak pointer for C to hold as a `uint64_t`. The object lives until `UniquePointer.adopt(w)` returns its owner, a reset or an unregistration of its allocator destroys it ([above](#objects-in-arenas-and-other-allocators)), or its home thread tears down ([above](#destroying-an-object)). `adopt` returns `nil` unless `w` names a live leaked object of type `T` whose home thread is the caller's, and a successful `adopt` ends the leak, so a forged, mistyped or repeated `adopt` is harmless, and so is one of an object never leaked. A leaked object is used through its weak pointers as any other. A `Shared` value crosses to C the same way ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)).

### Pinning for C

`stablePool.pin(h)` returns a move-only, unscoped **`Pin<T>?`**, `nil` for a stale handle, and `p.pin()` on an object's owner a **`LocalPin<T>`**, which works the same way but never leaves its object's home thread. While a pin lives, the address it holds is safe for C to use. A dense `Pool` can't pin, since removals move its elements. Pinning takes a shared `self`, so several threads may pin at once.

**A pin keeps its memory alive, independent of any owner.** While it lives:

- **The address is stable and valid.** It is `pin.address`, an `unsafe` field of type `*T`, so safe code never sees an address it could compare later.
- **Its memory is never freed or reused.** That holds whatever happens to the owner, the pool, the arena or any allocator the memory came from: destroying the object, destroying or clearing the `StablePool` (`p = StablePool()` included), resetting an arena, unregistering an allocator, or a `StablePool` removal wanting to reuse the slot. The release waits for the last pin, and each pin's drop happens before, in the memory model's order ([07](07-concurrency.md#atomics-and-locks)), the `deinit`, release or reuse that waited for it, so what a thread did through the address before the drop is done by then.
- **`deinit` waits for the last pin.** So C never reads a destroyed value. Destroying a pinned object retires it at once, so every weak pointer reads `nil`, but its `deinit` runs when the last pin drops, and a pin that is never dropped, such as one in a stale container, keeps it from running ([06](06-memory-and-allocators.md#stale-values-and-retired-objects)). `stablePool.remove(h)` on a pinned element does the same, and `stablePool.take(h)`, which moves the element out, returns `nil`.
- **The waiting `deinit` runs on the value's own thread when it is a thread-bound object's or isn't `Sendable`.** A thread-bound object's is queued to its home thread, and any other value that isn't `Sendable`, such as a `StablePool` element holding a `UniquePointer` or an OpenGL object, to the thread that retired it. The queued `deinit` runs at that thread's next outermost section entry, as for a thread-bound object ([above](#destroying-an-object)), or in its teardown if that comes first ([07](07-concurrency.md#global-state)). A `Sendable` value's runs on the reclaimer. So `Pin<T>` is `Sendable` when `T` is, since pin counts are atomic, and a `LocalPin<T>` never is, so it drops on its object's home thread, if it is dropped at all. A value that isn't `Sendable` is pinned only on its own thread.

**A pin guarantees memory, not immutability.** Rayo code can still mutate a pinned value or assign it a new one, whose old value's `deinit` runs at once, and C sees the new value at the same address. The pin covers the value's own memory, not the buffers it owns, which such a write may reallocate or free.
