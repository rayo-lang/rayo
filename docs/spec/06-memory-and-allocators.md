# 06 · Memory and allocators

Values that own heap storage need somewhere to allocate it and a defined way to release it. In Rayo, an allocator names where the storage comes from, every construction that gives a value storage says `alloc`, and an owning value remembers its allocator as it grows and is destroyed. An arena can reclaim many allocations at once, so resetting one also has to account for values and views that may still reach its memory.

```swift
let levelHeap = Allocator.register(TlsfHeap(size: 64.mb))   // a heap for level data
let scratch = Allocator.register(Arena(size: 64.mb))   // an arena for short-lived work

var props = levelHeap.alloc List<Prop>()          // an allocator named at the construction
var names = alloc List<String>()                  // the ambient allocator: .heap here

do {
    var visible = scratch.alloc List<Handle<Mesh>>()   // built in the scratch arena
    cull(scene, into: &visible)                        // grows there, though 'cull' names no allocator
    submit(visible.span)
}                                                      // 'visible' is destroyed here; freeing to an arena is a no-op

scratch.reset()                                        // everything the arena handed out is freed at once
```

`props` records `levelHeap` as its allocator, and `names` the ambient one, which outside an `Allocating` type's methods is `.heap`. `visible` records `scratch`, so `cull` grows it there without naming an allocator. After `visible` is destroyed, `scratch.reset()` reclaims the arena's storage. A reset that would invalidate a live use panics instead.

**Every heap allocation goes through an allocator the code shows**, in one of three ways ([Allocating with `alloc`](06-memory-and-allocators/allocator-basics.md#allocating-with-alloc)):

- a construction says `alloc`, with an allocator it names or the ambient one;
- a value grows through the allocator its construction showed;
- a closure converted to a `Closure` that owns its captures may allocate from the ambient allocator, which its type shows.

**Every release happens at a point the code shows**, where a value is destroyed:

- a scope end, an overwrite or a `consume`;
- a removal from a container;
- the drop of the last owner of a reference-counted value ([`Shared<T>`: data with many owners](06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)), or of the last pin ([03](03-handles-and-objects.md#pinning-for-c));
- a thread's end ([07](07-concurrency/global-state.md#thread-teardown));
- an arena reset or an unregistration.

**No release frees memory that a view, on any thread, may still read.** The compiler checks an owner's release, since destroying a value is a mutable access to its place, which no live borrow of the place allows ([01](01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). A reset or an unregistration frees memory that values anywhere may own, so it checks at run time first, and panics instead ([Arena safety: checked values and checked resets](06-memory-and-allocators/arena-safety.md#arena-safety-checked-values-and-checked-resets)).

## Subchapters

- [Allocator values and `alloc`](06-memory-and-allocators/allocator-basics.md)
- [Arena safety and allocator lifetimes](06-memory-and-allocators/arena-safety.md)
- [Allocator storage and implementations](06-memory-and-allocators/allocator-implementations.md)
- [Owning boxes and long-lived views](06-memory-and-allocators/owning-values.md)
- [Allocation failure and release](06-memory-and-allocators/allocation-lifecycle.md)
