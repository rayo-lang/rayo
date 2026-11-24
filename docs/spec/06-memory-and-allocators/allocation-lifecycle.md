# Allocation failure and release

[06 · Memory and allocators](../06-memory-and-allocators.md)

An owning value cannot proceed as though an allocation succeeded when it did not, or free storage before its contents are accounted for. Rayo lets code recover from allocation failure where it asks to. When storage is released, the value's destruction rules decide what must run first.

## Allocation failure

```rayo
func addSpawn(_ p: Vec3, to spawns: mutable &SoA<Vec3>) -> Void!AllocError {
    do {
        try spawns.tryAppend(p)         // the fallible form: fails with AllocError instead of ending the program
    } catch {
        evictUnusedAssets()             // make room, then try once more
        try spawns.tryAppend(p)         // a Vec3 is implicitly copyable, so each attempt appends a copy of 'p'
    }
}
```

**`alloc` ends the program when its allocator can't make the allocation, without unwinding** ([10](../10-errors-and-safety/panics.md#what-ends-the-program)). Every other allocating operation of the language's, or of a std type the language names, such as growing a `List`, does the same ([11](../11-compilation-model.md#the-prelude)). So no operation goes on with memory it didn't get. Those operations also have a fallible form, for code that can make room and try again, as `addSpawn` does. The fallible form returns `nil` or fails with `AllocError`, the prelude's error for an allocation its allocator couldn't make:

- `try alloc X(…)`, which fails with `AllocError` through the function's `!` result, as in `try alloc Box(v)` or `try level.alloc List<Prop>()` ([Allocating with `alloc`](allocator-basics.md#allocating-with-alloc));
- `try Closure.tryNew { … }`, for a closure whose conversion to a `Closure` may allocate, which has no `alloc` for a `try` to mark ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref));
- growing operations, which have no `alloc` either, such as the builtin `SoA`'s `try rows.tryAppend(x)` ([04](../04-types/data-layout.md#struct-of-arrays-soat));
- `Name(interning:)` ([04](../04-types/collections.md#collections-and-strings)), and `allocateRaw` and `reallocateRaw` ([10](../10-errors-and-safety/unsafe-code.md#raw-allocations)).

**One `try` covers both failures of `try alloc f(…)`, when `f` can fail itself.** The expression fails with the error union of `AllocError` and `f`'s failure type ([10](../10-errors-and-safety/typed-errors.md#error-unions)), as in `try alloc Blob.load(path)`, which can fail to read or to allocate. `try?` and `try!` apply to it as to any `try`.

## Releasing a value without destroying it: `TrivialFree`

```rayo
alloc func buildLevel(_ n: Int) -> Level!(IoError | ParseError) { … } // builds the level with the allocator its caller's alloc gives

world.level = try levelArena.alloc buildLevel(3)                      // in a function that can fail: the level's lists and strings come from the arena

levelArena.release(replace(mutable world.level, with: alloc Level())) // requires Level: TrivialFree; forgets the old level instead of destroying it
levelArena.reset()                                                    // what the arena holds goes stale, and its memory is freed
```

**The compiler derives `TrivialFree`, a marker protocol, for a type whose destruction does nothing but free memory**, as it derives `Frozen`: one in which every `deinit`, at any depth, is `PlainDeinit` ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)). So such a type holds none of these, whose destruction does more:

- an object owner, which destroys its object;
- a `Pin` or `LocalPin`, which unpins;
- a reference-counted pointer, such as a `Shared`, whose `deinit` changes a count that its other owners share.

**A `deinit` that a type hides counts too.** `Box<any P>` is `TrivialFree` only when `P` refines `TrivialFree`, or it is written `Box<any P & TrivialFree>`, as for `Frozen` ([`Frozen`: types with no interior mutability](owning-values.md#frozen-types-with-no-interior-mutability)). A `consuming` function value and a `Closure<F>`, which may own handed-over captures ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)), never are.

**`release` forgets the value instead of destroying it, and `reset` makes the memory reusable.** So `release` takes only a `TrivialFree` value, whose destruction would do nothing but free memory, which the reset then frees. Anything the value owns that didn't come from the arena leaks, and `release` `assert`s that nothing does ([10](../10-errors-and-safety/panics.md#assert-and-precondition)).
