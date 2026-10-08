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

**Every heap allocation goes through an allocator the code can name, and every release happens at a point the code shows**, where a value is destroyed:

- a scope end, an overwrite or a `consume`;
- a removal from a container;
- the drop of the last owner of a reference-counted value ([`Shared<T>`: data with many owners](06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)), or of the last pin ([03](03-handles-and-objects.md#pinning-for-c));
- a thread's end ([07](07-concurrency/global-state.md#thread-teardown));
- an arena reset or an unregistration.

**No release frees memory that a view, on any thread, may still read.** The compiler checks an owner's release, since destroying a value is a mutable access to its place, which no live borrow of the place allows ([01](01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). A reset or an unregistration frees memory that values anywhere may own, so it checks at run time first, and panics instead ([Arena safety: checked values and checked resets](06-memory-and-allocators/arena-safety.md#arena-safety-checked-values-and-checked-resets)).

## Subchapters

- [Allocator values and defaults](06-memory-and-allocators/allocator-basics.md)
- [Arena safety and allocator lifetimes](06-memory-and-allocators/arena-safety.md)
- [Allocator storage and implementations](06-memory-and-allocators/allocator-implementations.md)
- [Owning boxes and long-lived views](06-memory-and-allocators/owning-values.md)
- [Allocation failure and release](06-memory-and-allocators/allocation-lifecycle.md)
