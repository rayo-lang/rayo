# Allocation failure and release

[06 · Memory and allocators](../06-memory-and-allocators.md)

An owning value cannot proceed as though an allocation succeeded when it did not, or free storage before its contents are accounted for. Rayo lets code recover from allocation failure where it asks to, and `@noalloc` rules out allocation in a function. When storage is released, the value's destruction rules decide what must run first.

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

**An allocating operation of the language's, or of a std type the language names, such as `Box` or `Shared`, panics when its allocator can't make the allocation** ([11](../11-compilation-model.md#the-prelude)). So no operation goes on with memory it didn't get. Those operations that build or grow a value at run time also have a fallible form, for code that can make room and try again, as `addSpawn` does. The fallible form returns `nil` or throws `AllocError`, the prelude's error for an allocation its allocator couldn't make:

- `try Box.tryNew(v)`, `try Shared.tryNew(v)`, `try LocalShared.tryNew(v)` and `try UniquePointer.tryNew(v)`;
- `try Closure.tryNew { … }`, for a closure whose captures exceed the inline budget ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref));
- the builtin `SoA`'s growing operations, such as `try rows.tryAppend(x)` ([04](../04-types/data-layout.md#struct-of-arrays-soat));
- `Name(interning:)` ([04](../04-types/collections.md#collections-and-strings)), and `allocateRaw` and `reallocateRaw` ([10](../10-errors-and-safety/unsafe-code.md#raw-allocations)).

**`@noalloc` on a function makes any call in it that may allocate a compile error:**

```swift
@noalloc
func fillSilence(_ out: mutable MutableSpan<Float>, _ history: mutable List<Float>) {
    for i in 0..<out.count { out[i] = 0 }        // fine: nothing here allocates
    history.append(0)                            // error: 'append' may allocate, and 'fillSilence' is @noalloc
}
```

**In a `@noalloc` function, a call may allocate unless its callee is known statically and is itself `@noalloc`, or is a language operation that doesn't allocate**, such as integer arithmetic or indexing a span. That includes the calls the language makes for the code ([05](../05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures)), so `[1, 2] as List<_>` is an error there ([04](../04-types/collections.md#literals)). A call with no static callee is checked through its type:

- a call through a function value may allocate unless its type is `@noalloc` ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values));
- a call through `any P`, and a requirement call in generic code, may allocate unless the protocol declares the requirement `@noalloc`, which every witness to it must then be.

**Destroying a value may allocate unless each `deinit` it runs, at any depth, is `@noalloc` or `PlainDeinit`** ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)), since freeing memory isn't allocating.

- **Hidden `deinit`s.** So destroying a value of a type parameter may allocate, and so may destroying one whose type hides its `deinit`, such as a `Box<any P>` or a `Closure`. The exceptions are a `TrivialFree` type ([below](#releasing-a-value-without-destroying-it-trivialfree)), and a `Closure` whose function type is `@noalloc`, since only captures whose destruction passes the check move into one ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)).
- **Objects and pins.** Dropping an object's owner may allocate, since it may run the object's `deinit`. So may dropping a `Pin` or a `LocalPin`, since the last pin to drop runs the `deinit` its destruction left waiting.

**A call to C may allocate unless the import or the `extern c func` declares the function `noalloc` ([08](../08-c-interop/imports-and-inline-c.md#c-calls-in-noalloc-code-noalloc)), or it goes through a `@c noalloc` pointer ([05](../05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers)).**

**`@noalloc` doesn't cover attaching a thread.** A `@c` or `@export` function's first entry on a thread Rayo didn't create attaches that thread. That runs its thread-local initializers ([08](../08-c-interop/calling-rayo-from-c.md#c-entries-and-threads)), which may allocate, in a `@noalloc` function too.

## Releasing a value without destroying it: `TrivialFree`

```swift
using allocator = levelArena { world.level = loadLevel(3) }  // the level's lists and strings come from the arena

levelArena.release(replace(&world.level, with: Level()))     // requires Level: TrivialFree; forgets the old level instead of destroying it
levelArena.reset()                                           // what the arena holds goes stale, and its memory is freed
```

**The compiler derives `TrivialFree`, a marker protocol, for a type whose destruction does nothing but free memory**, as it derives `Frozen`: one in which every `deinit`, at any depth, is `PlainDeinit` ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)). So such a type holds none of these, whose destruction does more:

- an object owner, which destroys its object;
- a `Pin` or `LocalPin`, which unpins;
- a reference-counted pointer, such as a `Shared`, whose `deinit` changes a count that its other owners share.

**A `deinit` that a type hides counts too.** `Box<any P>` is `TrivialFree` only when `P` refines `TrivialFree`, or it is written `Box<any P & TrivialFree>`, as for `Frozen` ([`Frozen`: types with no interior mutability](owning-values.md#frozen-types-with-no-interior-mutability)). A `consuming` function value and a `Closure<F>`, which may own handed-over captures ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)), never are.

**`release` forgets the value instead of destroying it, and `reset` makes the memory reusable.** So `release` takes only a `TrivialFree` value, whose destruction would do nothing but free memory, which the reset then frees. Anything the value owns that didn't come from the arena leaks, and `release` `assert`s that nothing does ([10](../10-errors-and-safety/panics.md#assert-and-precondition)).
