# The law of exclusivity

[01 · Values and ownership](../01-values-and-ownership.md)

When two names reach the same storage, changing it through one can invalidate what the other still uses. Rayo limits which accesses may overlap. In this loop, removing an enemy would change the collection while the loop is borrowing it:

```swift
for (h, e) in &world.enemies.entries {
    if e.hp <= 0 {
        world.enemies.remove(h)            // error: 'world.enemies' is mutably borrowed by the loop
    }
}
```

**While a mutable borrow of a place is live, no other access to an overlapping place may happen. While a shared borrow is live, no mutable access may happen.** Moving from a place, assigning it and destroying it are mutable accesses to it, so an owner can't release or replace what a live borrow reaches.

Without the law, a change could destroy or move what a borrow still uses. In the loop above, `remove` would destroy the enemy that `e` lends, and may move the pool's last enemy into its slot ([03](../03-handles-and-objects.md#pools-and-handles)).

The compiler checks this one function at a time, from its body and the signatures of the functions it calls: a borrow never outlives the function that makes it, except as that function's signature says. So one body holds every borrow the check must see, and the check is **static, in every build, at no run-time cost**. Changing another field during the loop is allowed:

```swift
for (h, e) in world.enemies.entries {
    if e.hp <= 0 { world.commands.append(.despawn(h)) }  // a different field: allowed
}
world.apply(world.commands.take())                       // take() moves the contents out, leaving it empty
```

## State that other code can change

**Only these let other code change a value between two of your uses**, and each says so in its type or declaration:

- **Objects.** Code changes an object through its owner or any of its weak pointers, which are aliases the static checker can't see. So each access takes a mark, and a conflicting one panics ([03](../03-handles-and-objects.md#dynamic-exclusivity)).
- **Thread-locals.** A thread-local is declared `@threadlocal`, and the static checker can't see a callee touching one, so its accesses are marked the same way ([07](../07-concurrency/global-state.md#thread-locals)).
- **`Synchronized` values.** A value such as a `Mutex` changes only through its own synchronization ([07](../07-concurrency/synchronization.md#atomics-and-locks)). A `Slice` into a locked buffer takes the buffer's lock ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)).
- **Channel ends.** A channel's two ends share one queue, which each end changes ([07](../07-concurrency/synchronization.md#queues-and-channels)).
- **Pool elements.** A pool's element, named by a `Handle`, reads `nil` once the element is removed ([03](../03-handles-and-objects.md#pools-and-handles)).
- **Pinned elements.** C may hold a pinned element's address ([03](../03-handles-and-objects.md#pinning-for-c)).
- **Unsafe code.** In `unsafe` code, raw pointers, bare global `var`s and imported C variables let other code change a value, and nothing checks them.

## Which places overlap

The law of exclusivity governs accesses to overlapping places, so which places overlap decides which accesses conflict.

**Places overlap by path**: `world` and `world.enemies` overlap, since one contains the other.

- **Stored fields of one value are disjoint from each other**, since they occupy distinct bytes, and so are reflection projections of distinct stored fields, such as `value[f1]` and `value[f2]` ([09](../09-compile-time/reflection.md#what-reflection-can-read)). Two projections whose fields may be one overlap where the borrows are checked, as two that `Row.field(ofType:)` picks may in code generic over `Row`. `value[fields: (f1, f2)]` projects both at once, and is checked distinct at instantiation ([09](../09-compile-time/reflection.md#tuples-field-lists-and-queries)).
- **Inline array elements at indices known to differ where the borrows are checked are disjoint.** Any other two overlap, since `a[i]` and `a[j]` may be the same element. So may `a[I]` and `a[J]`, for value parameters `I` and `J` of a body checked once for all its instantiations ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)). A collection's elements are reached through its subscript, which is an accessor (next).
- **A user-declared computed property or subscript accessor is an access to all of `self`**, whatever it yields, since its body may reach any of it. So two `&` bindings of two computed properties of `world` conflict, as in the example below. An imported bitfield's generated accessors are the exception: each accesses only its C memory location (below), as a reflection projection of the bitfield does.

```swift
var p = &world.physics             // when 'physics' and 'render' are computed properties,
var r = &world.render              // error: each is an access to all of 'world', and 'p' is used below
p.step(dt)
```

**These places count as one place, since writing one can change another:**

- **Unions.** The members of one union, declared `union` or `@c union` or anonymous inside a struct ([04](../04-types/enums.md#untagged-unions), [08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)), and the fields nested at any depth inside them. Every rule that relies on disjoint fields treats a union this way, reflection projections and SoA splitting included.
- **Vector lanes.** The lanes of one `Simd` value ([04](../04-types/numbers-and-math.md#simd-and-math)), since storing one lane may rewrite the vector. A swizzle accesses the whole vector. `Vec3`'s `x`, `y` and `z` are ordinary stored fields, which are disjoint, and its swizzles are computed properties, which access all of it (above).
- **Enum payloads.** Reaching into a payload, an optional's included, reads the tag, which may be a niche inside the payload ([04](../04-types/enums.md#optionals)). So every path into one enum value's payload overlaps every other, through `?.`, `!`, a pattern or reflection's `value[case:]` ([09](../09-compile-time/reflection.md#what-reflection-can-read)): `s?.n` and `s?.b` conflict. One pattern that binds several parts reads the tag once, though, so one over an optional tuple gives two disjoint borrows, as in the example below.
- **Bitfields.** Imported bitfields that form one C **memory location** ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)). Bitfields in different memory locations, or a bitfield and a neighboring field, are separate places, which two threads may write at once, as C11 allows.

```swift
g(&e.f, &e.u)                            // error when 'f' and 'u' are members of one union
join({ e.f = 1 }, { use(e.u) })          // error: the same
join({ v.x = x }, { v.y = y })           // error for a Simd 'v': each closure accesses the whole vector
if var (first, second) = &pair { ... }   // fine for an optional tuple 'pair': two disjoint borrows
```

```c
struct { uint32_t a : 20; uint32_t b : 20; };  // 'a' and 'b' are one place, though they lie in two storage units
```

## Two elements of one collection

**Two elements at once need an API that checks at run time that they are distinct:**

```swift
if var (a, b) = &world.enemies[h1, h2] {     // nil if h1 == h2 or either is stale
    swap(&a.hp, &b.hp)
}
if var (a, b) = &verts[i, j] { ... }         // lists too: nil if i == j; out of bounds still panics
list.swapAt(i, j)
var (left, right) = list.split(at: mid)        // two disjoint MutableSpans, both depending on list
```
