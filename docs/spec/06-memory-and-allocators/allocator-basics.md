# Allocator values and `alloc`

[06 · Memory and allocators](../06-memory-and-allocators.md)

An owning value remembers where its storage came from so it can grow and release that storage through the same allocator. Every construction that gives a value storage says so with `alloc`, which names an allocator or takes the ambient one, so no allocator reaches code that doesn't show it.

## Allocator values

**An `Allocator` is a copyable id that names a registered allocator.** An owning value records the allocator its storage came from, and grows and frees through it. So the allocator isn't part of its type: a `List<Prop>` from `levelHeap` and one from `.heap` are the same type.

**Every registered allocator is either `.heap` or library code:**

- **`.heap`, the platform's general-purpose heap, has a fixed id and is never unregistered**, so its storage never goes stale: `Allocator.unregister(.heap)` panics. `Allocator.heap` is a `static const`, so code takes it with no `copy` ([01](../01-values-and-ownership/moving-values-out.md#constants)).
- **Every other registered allocator is library code implementing `AllocatorImpl`** ([Writing an allocator: `AllocatorImpl`](allocator-implementations.md#writing-an-allocator-allocatorimpl)). Examples are an arena, a heap or a budget wrapper, or one over a platform's memory APIs through `import c`.

**Every registered allocator is of one of three kinds, which say how the memory it hands out goes back:**

- A **heap**, such as `.heap` or a TLSF heap, frees each allocation individually.
- An **arena**, whose type conforms to `ArenaImpl`, hands out memory from blocks and frees nothing individually. Freeing into it is a no-op, and a **reset** frees everything it handed out at once ([What a reset does](arena-safety.md#what-a-reset-does)).
- A **wrapper**, such as a budget or a tracking allocator, passes another allocator's allocations through, so they go back as that allocator's do, and keeps accounts of them.

An allocator may draw its memory from one other allocator, its **backing**, such as the allocator a wrapper wraps ([Allocators over other allocators](allocator-implementations.md#allocators-over-other-allocators)).

## Allocating with `alloc`

```swift
var names = alloc List<String>()                     // storage from the ambient allocator (below)
var props = levelHeap.alloc List<Prop>()             // storage from levelHeap
var boss = alloc Box(Enemy(pos: spawn, hp: 5000))    // the enemy goes to the box's allocation
var loadout = alloc player.items.clone()             // the clone's buffer comes from the ambient allocator
let alive = scratch.alloc enemies.filter { $0.hp > 0 }     // a new list, in the scratch arena

var bare = List<Prop>()                              // error: making a 'List' needs 'alloc'
var boxed = alloc boss.value                         // error: 'Enemy' isn't Allocating; write 'alloc Box(…)'
```

**`alloc` marks every construction that gives a value heap storage.** `alloc X(…)` takes the storage from the ambient allocator ([below](#the-ambient-allocator)), and `a.alloc X(…)` from the allocator `a`. Either passes that allocator to what it calls, which is one of these:

- an initializer of a type that conforms to `Allocating` ([below](#the-allocating-protocol));
- an `alloc func`, which makes a new value for its caller, such as `clone()` or `filter` ([below](#functions-that-make-a-new-value-alloc-func));
- an array or dictionary literal, which then builds the `Allocating` type its position expects, such as a `List` or a `Map`, or a `List` from an array literal where nothing expects a type ([04](../04-types/collections.md#literals)).

**Each of those without `alloc` is a compile error**, such as `List<Prop>()`, `String("hp \(hp)")` or a bare `x.clone()` ([below](#functions-that-make-a-new-value-alloc-func)). So every value that owns storage shows where the storage comes from. A string literal isn't among them: it converts to a `String` as `ExpressibleByStringLiteral` says, with no `alloc` ([04](../04-types/collections.md#literals)).

**`alloc` applies to nothing else.** So `a.alloc f()` on a plain function `f`, one not declared `alloc func`, is a compile error. `alloc` never boxes a value either: `alloc` before a plain value, such as `boss.value` above, is a compile error, and boxing one is written `alloc Box(v)`. Only the `Box`'s contents go to the allocator. The `Box` itself is a small owning pointer that lives wherever it is put, as the inline part of every `Allocating` value does.

**`a.alloc` reads the id in `a` once, and holds no borrow of `a`.** The read needs no `copy` written, as a `static const` is taken ([01](../01-values-and-ownership/moving-values-out.md#constants)), and the value it makes keeps its own copy of the id.

**`alloc` ends the program when its allocator can't make the allocation, and `try alloc` fails instead** ([Allocation failure](allocation-lifecycle.md#allocation-failure)).

### The `Allocating` protocol

```swift
struct Inventory(var items: List<Item> = alloc List<Item>()): Allocating   // the compiler gives it its allocator

let inv = level.alloc Inventory()        // 'items' comes from 'level' too
```

**A type conforms to `Allocating` by declaring it, and declares nothing else for it.** The compiler gives the type its allocator as a field of its own, which its declaration and its initializers never mention. The field is the value's allocator word ([How values record their allocator](allocator-implementations.md#how-values-record-their-allocator)), which every allocating value carries and which a reset's checks read. So any type can hold an allocator, and the stale-value checks come with it. An open checks the storage reached through that word, as an `unsafe` core's open checks a raw allocation's ([10](../10-errors-and-safety/unsafe-code.md#raw-allocations)).

**Conforming is the type's choice, and it is always allowed.** It buys the caller the choice of allocator: a value of the type is made with `alloc`, and the allocator that `alloc` gives is the ambient one throughout the type's code. A type that doesn't conform is made without `alloc`, and its own allocations, its field defaults' included, take `.heap`, as any code outside an `Allocating` type's does. So a type that only holds `Allocating` values, such as an `Enemy` with a `List` of waypoints given to its initializer, needn't conform.

**The type's code reads its allocator as `self.allocator`**, an `Allocator` the compiler gives it, which no code assigns. So a type that allocates through raw memory passes it on, as in `self.allocator.allocateRaw(bytes: n, align: 8)` ([10](../10-errors-and-safety/unsafe-code.md#raw-allocations)).

**A field's default is part of the primary initializer**, so in an `Allocating` type its `alloc` takes the allocator the initializer received, as `items` does above ([04](../04-types/structs.md#initializers)). A secondary initializer's `self.init(…)` passes on the allocator that initializer received.

**std's owners and containers are all `Allocating`, and each is made the same way:**

- the owners `Box`, `UniquePointer`, `Shared` and `LocalShared`, as in `alloc Box(v)`, `alloc UniquePointer(Renderer(…))` or `level.alloc Shared(config)`;
- the containers `List`, `Map`, `Set`, `String`, `Pool`, `StablePool`, `TrailingArray` and `Blob`, as in `alloc Pool<Enemy>(capacity: 4096)`;
- the synchronized values that own buffers, `Published`, `MpscQueue` and `SpscQueue`, and channels, whose `Channel.make` is an `alloc func`, as in `alloc Channel<Request>.make(capacity: 64)` ([07](../07-concurrency/synchronization.md#queues-and-channels));
- the builtin `SoA`, as in `alloc SoA<Particle>()` ([04](../04-types/data-layout.md#struct-of-arrays-soat)).

### Functions that make a new value: `alloc func`

```swift
extension List {
    alloc func filter(_ keep: (Element) -> Bool) -> List<Element> where Element: Copyable {
        var out = alloc List<Element>()                  // the allocator the call received
        for x in self where keep(x) { out.append(copy x) }
        return out
    }
}
```

**A function that makes a new value for its caller is declared `alloc func`, and receives that value's allocator as a parameter**, which `alloc` fills at the call site. Initializers of an `Allocating` type receive one the same way, without the modifier. That covers `clone()`, and methods that build a new value from an existing one, such as `filter`, `concatenated` or `uppercased`: `alloc x.clone()`, `level.alloc xs.filter { … }`. A protocol requirement declared `alloc func` is witnessed only by an `alloc func`.

**An `alloc func` may return a value of any type**, so a move-only type's own `clone()` is an `alloc func` whether or not the type conforms to `Allocating`. Inside it, the allocator it received is the ambient one ([below](#the-ambient-allocator)).

**A plain function may still make an `Allocating` value and return it.** Its bare `alloc` takes `.heap`, whoever calls it, so its result's storage comes from `.heap` ([below](#the-ambient-allocator)). Its allocation shows in its body, not at its call, so a caller that needs to choose the allocator calls an `alloc func` instead.

**`clone()` is an `alloc func`**, so a bare `x.clone()` is a compile error. A clone's elements are cloned into the clone's allocator ([below](#the-ambient-allocator)).

## The ambient allocator

```swift
struct Level(var names: List<String> = alloc List<String>()): Allocating {
    mutating func addName(_ n: StringView) {
        names.append(alloc String(n))          // the level's allocator: the string goes where the list is
    }
    alloc func clone() -> Level {
        alloc Level(names: alloc names.clone())   // the received allocator: each part goes where the copy goes
    }
}

func report(_ level: Level) {
    var lines = alloc List<String>()           // a free function: .heap, even when a Level method calls it
    …
}
```

**`alloc` with no allocator named takes the ambient allocator, which the function it is written in decides:**

- **Inside an `alloc func` or an initializer of an `Allocating` type, it is the allocator the call received**, never the instance's. So no function that builds a copy reaches the source's allocator by default, and `alloc field.clone()` inside `clone()` puts each nested part where the copy goes.
- **Inside every other method of an `Allocating` type, it is the allocator `self` was allocated with.** So a value hands its allocator down to what it allocates: an `Inventory` made with `level.alloc Inventory()` makes its lists from `level`, and a level's `names.append(alloc String(n))` puts the string where the list is.
- **Everywhere else, it is `.heap`**, in a free function included, even one called from such a method.

A closure's body takes the ambient allocator of the function the closure is written in, since the rule follows where code is written.

**The ambient allocator is never a setting the program changes.** It follows from where the code is written, so code deep in a call tree allocates from an allocator only when the allocator reaches it through a value or an `alloc` its caller wrote.

### Growth

```swift
var spawns = scratch.alloc List<Vec3>()
spawns.append(.zero)                // grows through 'scratch', as the alloc at its construction showed
```

**A value grows through the allocator it holds, for its whole life.** `list.append(x)` may allocate with no `alloc`, through the allocator that the `alloc` at the list's construction showed, wherever the list is later grown.

### Allocations with no construction

A literal is never one of them, since it never allocates by itself ([04](../04-types/collections.md#literals)).

**Converting a closure to `Closure<F>`, which owns its captures, may allocate, and takes no `alloc`** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)). Whether it allocates depends on how much the closure captures, as whether `append` allocates depends on how many elements the list holds. So the type, `Closure<…>`, says that it may allocate, and `button.onClick { … }` may allocate with nothing at the call site, as `append` may. **The conversion allocates from the ambient allocator of the function it is written in** ([above](#the-ambient-allocator)).

**Two closures never allocate.** One is a closure passed as a plain function value, which is scoped and borrows its captures. The other is one held by its concrete type, `some F`, which stores its captures inline at any size ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)). Code that must not allocate holds a closure one of these ways.

**The runtime's own storage takes no `alloc`, and comes from `.heap`**, since no value the code makes owns it. That storage is:

- the `Name` interner ([04](../04-types/collections.md#collections-and-strings));
- tasks' wake targets ([07](../07-concurrency/tasks.md#running-tasks));
- lock guards' state.

### The static allocator

```swift
const primes: List<Int> = alloc makePrimes(below: 1000)    // built by the compiler; its buffer is in read-only data
var more = alloc primes.clone()                            // the clone's buffer comes from the ambient allocator
more.append(1009)                                          // and grows there, as any list's does
```

**Values in read-only data carry the static allocator, which never allocates or frees at run time.** They need an allocator, since every owning value records the one its storage came from ([How values record their allocator](allocator-implementations.md#how-values-record-their-allocator)). **Read-only data** holds the `const`s, and the global `let`s evaluated at compile time that pass the freezable test ([07](../07-concurrency/global-state.md#initialization-at-startup), [09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)). An `alloc` in a `const`'s initializer allocates from the compile-time heap, and its value is frozen into read-only data.

**Nothing consumes or mutates a value in read-only data, so it is never grown, and it is never destroyed** ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)). So nothing asks the static allocator to allocate or free at run time.

## Allocators and threads

**Every registered allocator must be safe to call from any thread**, since any thread can allocate through a copyable `Allocator` id, including lent work ([07](../07-concurrency/thread-work.md#lending-work-to-other-threads)). So `AllocatorImpl` refines `Synchronized`, the contract under which threads share a value through shared borrows ([07](../07-concurrency/synchronization.md#the-synchronized-contract)). Its methods are non-`mutating`, and change its state only through its own synchronization: atomics, a lock, or state kept per thread inside the implementation.
