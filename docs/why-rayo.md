# Why Rayo

The [README](../README.md) introduces Rayo. This page makes the case for it: the six principles behind its trade-offs, the problems it answers in C++, Rust, Swift and C#, and a small game that shows most of its ideas at once. The spec chapters it links to define every rule it mentions.

## Design pillars

Six principles decide Rayo's trade-offs.

1. **Costs are visible.** Allocation, dynamic dispatch, copies and unsafe memory access are spelled out in source. Nothing implicitly counts references, boxes or collects garbage. Nothing copies beyond what 01 lists ([01](spec/01-values-and-ownership/moves-copies-destruction.md#operations-that-copy)), with two exceptions:
    - a `String` made from a literal, as in `alloc "jump"`, copies the literal's bytes at its first write or growth ([04](spec/04-types/collections.md#strings));
    - a closure moved into a `Closure` may put the captures its capture list shows in an allocated context, which the `Closure` type shows and no `alloc` marks ([05](spec/05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).

   Where the compiler stages a place through a temporary, a declaration announces it:
    - a `@layout(.packed)` struct ([04](spec/04-types/structs.md#packed-structs-and-under-aligned-places));
    - an imported C bitfield ([08](spec/08-c-interop/imports-and-inline-c.md#structs-unions-and-enums));
    - a value property, one declared with `get` and `set` ([02](spec/02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)).

   A place property, declared with `borrow` and `mutate`, never stages: it hands out its storage itself ([02](spec/02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate)).
2. **Nothing reasonable is forbidden; the language only chooses how to check it.** Each systems pattern lands in the cheapest [tier](spec/01-values-and-ownership.md#tiers-of-checking) that can check it, and none is forced into `unsafe` just because the checker can't prove it.
3. **Values by default, objects when you need them.** Borrows of values are checked within one function body. Longer links are handles and weak pointers, checked at each use.
4. **No build setting turns memory safety off; diagnostics are settings.** Bounds checks, object checks and arena checks stay on in every build, except the ones an `unchecked` block's own code performs ([10](spec/10-errors-and-safety/checks-and-build-modes.md#unchecked-blocks)). Diagnostic checks, such as overflow and `assert`, are on or off where code is written, by the build mode's default, a module's settings or a scope's `@checks` ([10](spec/10-errors-and-safety/checks-and-build-modes.md#check-levels)).
5. **Rayo calls C and exports C.** So every platform SDK is reachable. It has no C++ interop, which lets it define its semantics from scratch, and reaches C++-only APIs through a thin C wrapper.
6. **Edit-build-run cycles are fast.** Type checking needs no search, and no build does work beyond what 11 lists ([11](spec/11-compilation-model.md#runtime-costs)), so unoptimized builds stay fast enough to test with.

## Problems Rayo answers

### C++'s problems

| Problem | Rayo's answer | Spec |
| --- | --- | --- |
| Memory bugs compile silently: use-after-free, dangling pointers, iterator invalidation, out-of-bounds writes, surfacing as crashes far from their cause, sometimes only in release builds or on one platform. | Safe code can't produce them. Borrows are checked at compile time, stored links read `nil` or panic, and bounds checks stay on in release builds. `unsafe` marks what the compiler trusts, and a `@safe` module can't use it. | [01](spec/01-values-and-ownership.md), [10](spec/10-errors-and-safety.md) |
| Data races in job code compile silently, found by ThreadSanitizer and code review, if at all. | The exclusivity check is the race check: two closures handed to a job system that touch the same data, one writing, don't compile. What isn't `Sendable`, such as a pointer to a thread-bound object, can't reach another thread. | [07](spec/07-concurrency/thread-work.md#lending-work-to-other-threads) |
| Undefined behavior in everyday operations (signed overflow, strict aliasing, uninitialized reads) and unspecified evaluation order, which optimizers exploit, and float expressions that each compiler fuses into multiply-adds by its own rules, so debug and release builds, or two platforms' compilers, can disagree. | Safe code has no undefined behavior. Integer operations have defined results, evaluation is left to right, and raw pointers have no type-based aliasing rule. Basic float arithmetic is never fused or reordered, so it gives the same bits everywhere (a NaN's sign and payload aside), and an explicit `fma` rounds a multiply-add once, with the same bits on every target. | [01](spec/01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin), [04](spec/04-types.md) |
| Build times: every translation unit re-parses headers and re-instantiates templates. | Modules checked against each other's public declarations, and generics type-checked once, at their definition. | [11](spec/11-compilation-model.md#type-checking-is-local) |
| No reflection: large codebases generate metadata with header tools, code generators and macros, such as Qt's `moc`, protobuf's and other serializers' generated code, and Unreal's UHT and `UPROPERTY`. | Static reflection, user-defined attributes, and `static for` over code and declarations, which [generates types](spec/09-compile-time/declaration-generation.md#generating-declarations) as well as code. | [09](spec/09-compile-time.md) |
| A standard library that performance-critical code routes around: implicit container copies, allocating `std::function`s, exceptions and RTTI usually off, allocators in a container's type outside `std::pmr`. Many codebases rewrite the containers (EASTL, Unreal's `TArray`). | Copying heap data, allocation and dynamic dispatch are visible in source, every owning collection takes an allocator without changing its type, and errors are typed return values. | [01](spec/01-values-and-ownership.md), [06](spec/06-memory-and-allocators.md), [10](spec/10-errors-and-safety.md) |
| A moved-from object is "valid but unspecified", and nothing stops code from using it. | A moved-from variable or field is statically dead until it is assigned again. | [01](spec/01-values-and-ownership/moves-copies-destruction.md#moves) |

### Rust's problems

| Problem | Rayo's answer | Spec |
| --- | --- | --- |
| Borrow checker vs. shared, mutable, cyclic object graphs | Borrows are checked within a function, with no lifetime annotations. Stored links (parents, observers, services, cycles) are handles or weak pointers, in the dynamic tier. Any graph is expressible in safe code. | [02](spec/02-views-and-dependencies.md), [03](spec/03-handles-and-objects.md) |
| Slow compiles | No trait solver or lifetime inference, one-directional local inference, generics checked once. | [11](spec/11-compilation-model.md#type-checking-is-local) |
| Unsafe is harder than C++ (two live `&mut` are instant undefined behavior; Miri can't run code that calls platform SDKs) | Raw pointers follow six stated rules (in bounds, aligned, valid, whole, race-free, exposed), with no hidden `noalias` and no type-based aliasing. Its aliasing promises are the ones borrows, bindings and views make. | [10](spec/10-errors-and-safety/unsafe-code.md#raw-accesses), [10](spec/10-errors-and-safety/unsafe-code.md#aliasing-and-skipped-deinits) |
| The allocator API for std collections is unstable | Allocators are stable values that every owning collection records, every construction that allocates says `alloc`, and arena resets are memory-safe. | [06](spec/06-memory-and-allocators.md) |
| A hash map built at compile time needs an external crate, such as `phf` | A `const` `Map` that names `FixedHashing` is built by ordinary code in the compiler and frozen into read-only data. The default hashing is still seeded for each map, as `RandomState` is. | [04](spec/04-types/collections.md#hash-maps-and-sets) |
| Portable SIMD is unstable | SIMD vectors of up to 64 lanes are built in, with shuffles, swizzles, masks and reductions. | [04](spec/04-types/numbers-and-math.md#simd-and-math), [08](spec/08-c-interop.md) |
| Steep learning curve for large, mixed teams | Swift-shaped syntax and three tiers instead of lifetimes, variance and pinned self-references, with one derived `Sendable` marker where Rust has `Send` and `Sync`. The binding says whether it moves, copies or borrows, whatever the type: `let b = a`, `let b = copy a`, `let b = borrow a`. | [01](spec/01-values-and-ownership.md) |

### Swift's problems

| Problem | Rayo's answer | Spec |
| --- | --- | --- |
| ARC retain/release traffic; the optimizer moves refcounts between builds | No implicit reference counting: only reference-counted pointers such as `Shared<T>` count, where the code makes an owner. Handing a value over moves it, and every copy is written out. | [01](spec/01-values-and-ownership.md) |
| ARC cycles leak unless code marks each back-reference `weak` or `unowned` | Stored references (weak pointers, handles) own nothing, so a back-reference never keeps its target alive, and a dead target reads `nil`. | [03](spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert) |
| Release cascades free big graphs synchronously | Arenas reset in O(1), and a `TrivialFree` value is released into its arena without walking it. Ownership moves, so a library can also destroy a value later or a piece at a time. | [06](spec/06-memory-and-allocators/allocation-lifecycle.md#releasing-a-value-without-destroying-it-trivialfree) |
| Unspecialized generics, existentials, exclusivity and COW checks appear after harmless changes | Generics are always monomorphized, `any P` is written out and never boxes implicitly, dynamic exclusivity checks run only where a type or declaration announces them, and there is no copy-on-write, only the one deferred copy a `String` made from a plain literal or a static view takes, as `alloc "jump"` does, with no count to check ([04](spec/04-types/collections.md#strings)). | [03](spec/03-handles-and-objects.md#dynamic-exclusivity), [05](spec/05-protocols-generics-and-closures.md) |
| Unoptimized builds are dramatically slower | No build makes runtime calls beyond the ones [11](spec/11-compilation-model.md#runtime-costs) lists, and generic code is always specialized. | [11](spec/11-compilation-model.md#runtime-costs) |
| Slow type checking | No bidirectional constraint solver, bounded operator lookup, and one local step to type each literal. | [11](spec/11-compilation-model.md#type-checking-is-local) |
| No per-container allocators | Same answer as for Rust | [06](spec/06-memory-and-allocators.md) |
| Async functions keep their frames in task memory that the runtime allocates, and actors don't fit fork-join job graphs | For job graphs, std's structured concurrency (`join`, parallel loops, scoped threads), race-free under the ordinary borrow and closure rules. For I/O and other waiting, [`task` coroutines](spec/07-concurrency/tasks.md#waking-a-task) whose size is known at compile time, which never allocate on their own. A task hands its `Waker` to whatever it waits on, such as an I/O library, which wakes it once its socket or file is ready, and std's runners wake it at a deadline. The program runs its tasks itself: once a frame with `step`, from its own event loop, or with `run`, which parks the thread until a task is woken. | [07](spec/07-concurrency.md) |

### C#'s problems

| Problem | Rayo's answer | Spec |
| --- | --- | --- |
| GC pauses at times you don't choose | No GC. Memory is released at points visible in source: a scope end, an overwrite, a `consume`, a removal from a container, the drop of a reference-counted value's last owner, a thread's end, an arena reset or an unregistration. A reset or an unregistration never frees memory a view, on any thread, may still read: it panics instead. | [03](spec/03-handles-and-objects.md#destroying-an-object), [06](spec/06-memory-and-allocators/arena-safety.md#arena-safety-checked-values-and-checked-resets) |
| Closed platforms such as consoles and iOS forbid JIT, so C# reaches them only through a separate ahead-of-time toolchain, such as IL2CPP, with its own runtime | Nothing in Rayo generates code while a program runs, so every program compiles ahead of time and no target needs a JIT or a separate toolchain. The runtime needs only a few services from the platform. | [11](spec/11-compilation-model.md#what-a-target-must-provide), [08](spec/08-c-interop/c-contract-and-embedding.md#what-the-runtime-needs-from-the-platform) |

## A taste

A tiny game: enemies chase a player, updated on several threads at once, and a scripted door opens over several frames.

```swift
import std.math                             // normalized and other vector math
import std.pool                             // Pool; Handle is in the prelude
import std.jobs                             // forEachInParallel, from std's job system
import std.tasks                            // TaskSet, elapsed(_:)
import engine.editor                        // the engine's own Bounds attribute
import c "platform.h" as plat where prefix: "platform_"   // a C header: platform_time_seconds() is plat.time_seconds()

// Game data is ordinary values, and the pools in World own them.
@reflect(private)                           // lets reflective code in other modules, such as the editor, see every field
struct Enemy(
    var pos: Vec3,
    var vel: Vec3 = .zero,
    @Bounds(0, 500) var hp: Float = 100,   // a user-defined attribute, which the editor reads through reflection
    var target: Handle<Player>?,            // goes stale if the player is removed, never dangles
)

struct Player(var pos: Vec3)
enum DoorState { case closed, opening, open }
struct Door(var state: DoorState = .closed)

// All the game's state, passed explicitly to the code that needs it.
struct World(
    var players = alloc Pool<Player>(),     // a Pool stores its elements densely and hands out Handles to them
    var enemies = alloc Pool<Enemy>(capacity: 4096),
    var doors = alloc Pool<Door>(),
    var clock = Instant<World>(nanoseconds: 0),   // simulation time, on the World's own clock
)

extension World: TimeSource {               // what elapsed(_:) counts in: here, simulation time
    var now: Instant<World> { copy clock }  // a copy, written out: the World keeps its clock
}

// Moves every enemy toward its target.
func steer(_ world: mutable World, dt: Float) {
    world.enemies.forEachInParallel { e in                   // e: one enemy, borrowed mutably
        guard e.target != nil, let p = world.players[e.target]     // a stale handle reads nil: skip this enemy
        else { return }
        e.vel = (p.pos - e.pos).normalized * 4
        e.pos += e.vel * dt
    }
}

// A script that plays out over several frames. Calling openDoor(d) runs nothing yet:
// it returns the task's state, and whoever holds that state steps it.
task func openDoor(_ door: owned Handle<Door>) with (world: mutable World) {   // owns its door; each step lends it the World
    world.doors[door]?.state = .opening     // '?': does nothing if the door is gone
    await elapsed(.seconds(0.5))            // suspends until a step finds half a second of world time has passed
    world.doors[door]?.state = .open        // no borrow survives an await: 'world' is re-lent on resume
}

func main() {
    var world = World()
    let hero = world.players.insert(Player(pos: .zero))              // insert returns a Handle<Player>
    _ = world.enemies.insert(Enemy(pos: Vec3(10, 0, 0), target: hero))   // an enemy that chases the hero; its handle isn't needed
    let gate = world.doors.insert(Door())

    var scripts = TaskSet<World>(capacity: 64)                       // a set of tasks stepped with a World
    _ = scripts.start(openDoor(gate))                                // the set runs it; this code needs no handle to it

    var last = unsafe plat.time_seconds()   // calling C is unsafe: the compiler can't check C code
    while true {
        let now = unsafe plat.time_seconds()
        world.clock += Duration.seconds(now - last)
        steer(&world, dt: Float(now - last)) // '&' marks a mutable borrow
        scripts.step(&world)                // runs each woken script to its next await that isn't done
        last = now
    }
}
```

What it shows:

- **Values and handles.** Game data is ordinary values in `Pool`s. An enemy's `target` is a `Handle`, so once the player is removed, `world.players[t]` reads `nil`. `hero` moves into the new enemy, and `copy clock` is a copy written out ([01](spec/01-values-and-ownership/moves-copies-destruction.md#copies)).
- **Race-free parallel loops.** The closure in `steer` runs on several threads at once. It compiles because it writes only its own enemy and only reads `world.players`; also writing `world.players` would be a compile error ([07](spec/07-concurrency/thread-work.md#lending-work-to-other-threads)).
- **Tasks.** `openDoor` pauses at `await`, and continues when it is woken and its owner steps it. Its wait counts the world's own time, so it wakes itself at every pass of the main loop, and each pass checks the clock. It holds no borrow across an `await`, so it never keeps a stale pointer into `world` ([07](spec/07-concurrency/tasks.md#semantics)).
- **Reflection and attributes.** `Bounds` is an ordinary struct used as an attribute. The editor finds it by reflecting over `Enemy`'s fields, and `@reflect(private)` lets it see fields that aren't public ([09](spec/09-compile-time.md)).
- **C, called directly.** `import c` makes a header's declarations available, and every call into C is `unsafe` ([08](spec/08-c-interop.md)).

