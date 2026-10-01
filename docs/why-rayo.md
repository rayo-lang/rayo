# Why Rayo

The [README](../README.md) introduces Rayo. This page makes the case for it: the six principles behind its trade-offs, the problems it answers in C++, Rust, Swift and C#, and a small game that shows most of its ideas at once. The spec chapters it links to define every rule it mentions.

## Design pillars

Six principles decide Rayo's trade-offs.

1. **Costs are visible.** Allocation, dynamic dispatch, copies and unsafe memory access are spelled out in source. Nothing implicitly counts references, boxes or collects garbage, and nothing copies beyond what [01](spec/01-values-and-ownership.md) lists, except that a `String` made from a literal copies the literal's bytes at its first write or growth ([04](spec/04-types.md#literals)), and a closure moved into a `Closure` puts the captures its capture list shows in an allocated context when they don't fit inline ([05](spec/05-protocols-generics-and-closures.md#unscoped-closures-closuref)). Where the compiler stages a place through a temporary, a declaration announces it: a `@packed` struct ([04](spec/04-types.md#packed-structs-and-under-aligned-places)), an imported C bitfield ([08](spec/08-c-interop.md#structs-unions-and-enums)), a property or subscript with a `set` ([02](spec/02-views-and-dependencies.md#get-and-set-accessors)), or an access-bound `read` or `modify` that yields a temporary ([02](spec/02-views-and-dependencies.md#projections-read-and-modify-accessors)).
2. **Nothing reasonable is forbidden; the language only chooses how to check it.** Each systems pattern lands in the cheapest [tier](spec/01-values-and-ownership.md#tiers-of-checking) that can check it, and none is forced into `unsafe` just because the checker can't prove it.
3. **Values by default, objects when you need them.** Borrows of values are checked within one function body. Longer links are handles and weak pointers, checked at each use.
4. **No build setting turns memory safety off; diagnostics are settings.** Bounds checks, object checks and arena checks stay on in every build, except the ones an `unchecked` block's own code performs ([10](spec/10-errors-and-safety.md#choosing-checks-for-a-module-or-a-scope)). Diagnostic checks, such as overflow and `assert`, are on or off where code is written, by the profile's default, a module's settings or a scope's `@checks` ([10](spec/10-errors-and-safety.md#check-levels)).
5. **Rayo calls C and exports C.** So every platform SDK is reachable. It has no C++ interop, which lets it define its semantics from scratch, and reaches C++-only APIs through a thin C wrapper.
6. **Edit-build-run cycles are fast.** Type checking needs no search, and no build does work beyond what [11](spec/11-compilation-model.md#runtime-costs) lists, so unoptimized builds stay fast enough to test with.

## Problems Rayo answers

### C++'s problems

| Problem | Rayo's answer | Spec |
| --- | --- | --- |
| Memory bugs compile silently: use-after-free, dangling pointers, iterator invalidation, out-of-bounds writes, surfacing as crashes far from their cause, sometimes only in release builds or on one platform. | Safe code can't produce them. Borrows are checked at compile time, stored links read `nil` or panic, and bounds checks stay on in shipping builds. `unsafe` marks what the compiler trusts, and a `@safe` module can't use it. | [01](spec/01-values-and-ownership.md), [10](spec/10-errors-and-safety.md) |
| Data races in job code compile silently, found by ThreadSanitizer and code review, if at all. | The exclusivity check is the race check: two closures handed to a job system that touch the same data, one writing, don't compile. What isn't `Sendable`, such as a pointer to a thread-bound object, can't reach another thread. | [07](spec/07-concurrency.md#lending-work-to-other-threads) |
| Undefined behavior in everyday operations (signed overflow, strict aliasing, uninitialized reads) and unspecified evaluation order, which optimizers exploit, so debug and release builds, or two platforms' compilers, can disagree. | Safe code has no undefined behavior. Integer operations have defined results, evaluation is left to right, basic float arithmetic gives the same bits everywhere (a NaN's sign and payload aside), and raw pointers have no type-based aliasing rule. | [01](spec/01-values-and-ownership.md#evaluation-order-and-when-a-calls-borrows-begin), [04](spec/04-types.md) |
| Build times: every translation unit re-parses headers and re-instantiates templates. | Modules checked against each other's public declarations, and generics type-checked once, at their definition. | [11](spec/11-compilation-model.md#type-checking-is-local) |
| No reflection: large codebases generate metadata with header tools and macros, such as Unreal's UHT and `UPROPERTY`. | Static reflection, user-defined attributes, and `static for` over code and declarations, which [generates types](spec/09-compile-time.md#generating-declarations) as well as code. | [09](spec/09-compile-time.md) |
| A standard library that performance-critical code routes around: implicit container copies, allocating `std::function`s, exceptions and RTTI usually off, allocators in a container's type outside `std::pmr`. Many codebases rewrite the containers (EASTL, Unreal's `TArray`). | Copying heap data, allocation and dynamic dispatch are visible in source, every owning collection takes an allocator without changing its type, and errors are typed return values. | [01](spec/01-values-and-ownership.md), [06](spec/06-memory-and-allocators.md), [10](spec/10-errors-and-safety.md) |
| A moved-from object is "valid but unspecified", and nothing stops code from using it. | A moved-from variable or field is statically dead until it is assigned again. | [01](spec/01-values-and-ownership.md#moving-values-out) |

### Rust's problems

| Problem | Rayo's answer | Spec |
| --- | --- | --- |
| Borrow checker vs. shared, mutable, cyclic object graphs | Borrows are checked within a function, with no lifetime annotations. Stored links (parents, observers, services, cycles) are handles or weak pointers, in the dynamic tier. Any graph is expressible in safe code. | [02](spec/02-views-and-dependencies.md), [03](spec/03-handles-and-objects.md) |
| Slow compiles | No trait solver or lifetime inference, one-directional local inference, generics checked once. | [11](spec/11-compilation-model.md#type-checking-is-local) |
| Unsafe is harder than C++ (two live `&mut` are instant undefined behavior; Miri can't run code that calls platform SDKs) | Raw pointers follow six stated rules (in bounds, aligned, valid, whole, race-free, exposed), with no hidden `noalias` and no type-based aliasing. Its aliasing promises are the ones borrows, bindings and views make. | [10](spec/10-errors-and-safety.md#unsafe-code) |
| The allocator API for std collections is unstable | Allocators are stable values that every owning collection takes, a scoped `using` sets the default, and arena resets are memory-safe. | [06](spec/06-memory-and-allocators.md) |
| No official targets for closed platforms, such as consoles, whose SDKs are under NDA; std needs porting | Every feature can be implemented in portable C, so a toolchain can build Rayo with the platform's own C compiler instead of porting LLVM, and the runtime needs only a few services from the platform. | [11](spec/11-compilation-model.md#what-a-target-must-provide), [08](spec/08-c-interop.md#the-platform-and-embedding-rayo-in-c) |
| Portable SIMD is unstable | SIMD vectors and swizzles are built in. | [04](spec/04-types.md#simd-and-math), [08](spec/08-c-interop.md) |
| Steep learning curve for large, mixed teams | Swift-shaped syntax and three tiers instead of lifetimes, variance and pinned self-references, with one derived `Sendable` marker where Rust has `Send` and `Sync`. The binding says whether it borrows, moves or copies, whatever the type: `let b = a`, `owned let b = a`, `let b = copy a`. | [01](spec/01-values-and-ownership.md) |

### Swift's problems

| Problem | Rayo's answer | Spec |
| --- | --- | --- |
| Porting the compiler and runtime to each closed platform under NDA | Same answer as for Rust's closed-platform targets | [11](spec/11-compilation-model.md#what-a-target-must-provide) |
| ARC retain/release traffic; the optimizer moves refcounts between builds | No implicit reference counting: only reference-counted pointers such as `Shared<T>` count, where the code makes an owner. Handing a value over moves it, and every copy is written out. | [01](spec/01-values-and-ownership.md) |
| ARC cycles leak unless code marks each back-reference `weak` or `unowned` | Stored references (weak pointers, handles) own nothing, so a back-reference never keeps its target alive, and a dead target reads `nil`. | [03](spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert) |
| Release cascades free big graphs synchronously | Arenas reset in O(1), and a `TrivialFree` value is released into its arena without walking it. Ownership moves, so a library can also destroy a value later or a piece at a time. | [06](spec/06-memory-and-allocators.md#releasing-a-value-without-destroying-it-trivialfree) |
| Unspecialized generics, existentials, exclusivity and COW checks appear after harmless changes | Generics are always monomorphized, `any P` is written out and never boxes implicitly, dynamic exclusivity checks run only where a type or declaration announces them, and there is no copy-on-write, only a literal `String`'s one copy of its literal's bytes, with no count to check ([04](spec/04-types.md#literals)). | [03](spec/03-handles-and-objects.md#dynamic-exclusivity), [05](spec/05-protocols-generics-and-closures.md) |
| Unoptimized builds are dramatically slower | No build makes runtime calls beyond the ones [11](spec/11-compilation-model.md#runtime-costs) lists, and generic code is always specialized. | [11](spec/11-compilation-model.md#runtime-costs) |
| Slow type checking | No bidirectional constraint solver, bounded operator lookup, and one local step to type each literal. | [11](spec/11-compilation-model.md#type-checking-is-local) |
| No per-container allocators | Same answer as for Rust | [06](spec/06-memory-and-allocators.md) |
| Actors and async/await suit I/O, not fork-join job graphs | std's structured concurrency (`join`, parallel loops, scoped threads), race-free under the ordinary borrow and closure rules, and [`task` coroutines](spec/07-concurrency.md#semantics) the program steps explicitly. | [07](spec/07-concurrency.md) |

### C#'s problems

| Problem | Rayo's answer | Spec |
| --- | --- | --- |
| GC pauses at times you don't choose | No GC. Memory is released at points visible in source: a scope end, an overwrite, a `consume`, a removal from a container, the drop of a reference-counted value's last owner, a thread's end, an arena reset or an unregistration. A reset or an unregistration never frees memory a view, on any thread, may still read: it panics instead. | [03](spec/03-handles-and-objects.md#destroying-an-object), [06](spec/06-memory-and-allocators.md#arena-safety-checked-values-and-checked-resets) |
| Closed platforms such as consoles and iOS forbid JIT, so C# reaches them only through a separate ahead-of-time toolchain, such as IL2CPP, with its own runtime | Same answer as for Rust's closed-platform targets | [11](spec/11-compilation-model.md#what-a-target-must-provide) |

## A taste

A tiny game: enemies chase a player, updated on several threads at once, and a scripted door opens over several frames.

```swift
import std.math                             // normalized and other vector math
import std.pool                             // Pool; Handle is in the prelude
import std.jobs                             // forEachInParallel, from std's job system
import std.tasks                            // TaskSet, seconds(_:)
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
    var players = Pool<Player>(),           // a Pool stores its elements densely and hands out Handles to them
    var enemies = Pool<Enemy>(capacity: 4096),
    var doors = Pool<Door>(),
    var clock: Double = 0,                  // simulation time, in seconds
)

extension World: TimeSource {               // what seconds(_:) counts in: here, simulation time
    var now: Double { copy clock }          // a copy, written out: the World keeps its clock
}

// Moves every enemy toward its target.
func steer(_ world: mutable World, dt: Float) {
    world.enemies.forEachInParallel { e in                   // e: one enemy, borrowed mutably
        guard let t = e.target, let p = world.players[t]     // a stale handle reads nil: skip this enemy
        else { return }
        e.vel = (p.pos - e.pos).normalized * 4
        e.pos += e.vel * dt
    }
}

// A script that plays out over several frames. Calling openDoor(d) runs nothing yet:
// it returns the task's state, and whoever holds that state steps it.
task func openDoor(_ door: owned Handle<Door>) with (world: mutable World) {   // owns its door; each step lends it the World
    world.doors[door]?.state = .opening     // '?': does nothing if the door is gone
    await seconds(0.5)                      // suspends until a step finds half a second of world time has passed
    world.doors[door]?.state = .open        // no borrow survives an await: 'world' is re-lent on resume
}

func main() {
    var world = World()
    let hero = world.players.insert(Player(pos: .zero))              // insert returns a Handle<Player>
    world.enemies.insert(Enemy(pos: Vec3(10, 0, 0), target: hero))   // an enemy that chases the hero
    let gate = world.doors.insert(Door())

    var scripts = TaskSet<World>(capacity: 64)                       // a set of tasks stepped with a World
    scripts.start(openDoor(gate))

    var last = unsafe plat.time_seconds()   // calling C is unsafe: the compiler can't check C code
    while true {
        let now = unsafe plat.time_seconds()
        world.clock += now - last
        steer(&world, dt: Float(now - last)) // '&' marks a mutable borrow
        scripts.step(&world)                // runs each script to its next await that isn't done
        last = now
    }
}
```

What it shows:

- **Values and handles.** Game data is ordinary values in `Pool`s. An enemy's `target` is a `Handle`, so once the player is removed, `world.players[t]` reads `nil`. `hero` moves into the new enemy, and `copy clock` is a copy written out ([01](spec/01-values-and-ownership.md#values)).
- **Race-free parallel loops.** The closure in `steer` runs on several threads at once. It compiles because it writes only its own enemy and only reads `world.players`; also writing `world.players` would be a compile error ([07](spec/07-concurrency.md#lending-work-to-other-threads)).
- **Stepped tasks.** `openDoor` pauses at `await` and continues when its owner steps it, here once per pass of the main loop. It holds no borrow across an `await`, so it never keeps a stale pointer into `world` ([07](spec/07-concurrency.md#semantics)).
- **Reflection and attributes.** `Bounds` is an ordinary struct used as an attribute. The editor finds it by reflecting over `Enemy`'s fields, and `@reflect(private)` lets it see fields that aren't public ([09](spec/09-compile-time.md)).
- **C, called directly.** `import c` makes a header's declarations available, and every call into C is `unsafe` ([08](spec/08-c-interop.md)).

