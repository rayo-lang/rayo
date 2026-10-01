# Hard cases

This file is a validation suite for the Rayo spec (`docs/01`–`14`). Each case names a capability that systems code needs, chosen because a mainstream language forbids it, makes it painful, or makes it unsafe. A case's examples show one instance of the capability, and its criteria hold for every instance. For each case, a validator writes the Rayo code the spec allows and judges it against the case's pass criteria. The spec is the only source of truth: a case that needs a feature the spec doesn't define fails.

The cases test Rayo's governing rule ([14](14-decisions.md) D0): **no reasonable systems pattern is forbidden**, and each lands in the cheapest of the three [tiers](01-values-and-ownership.md#tiers-of-checking) that can check it.

## How to validate

Each case is a capability, with the patterns that exercise it, and a validator grades it with a verdict (below). The cases test what the rules let code express; why everything they accept is sound is argued in [15](15-soundness.md).

Terms the cases and criteria use:

- A **view** is a value that borrows memory something else owns, such as a `Span<T>` of a list's elements or a `StringView` of a string's text.
- A **scoped** value, one whose type conforms to `Scoped`, must stay within the scope that lent it, as every view that borrows memory that can be freed must ([02](02-views-and-dependencies.md#scoped-values)).
- A `Handle<T>` is a small checked index into a pool of `T`s.
- A `UniquePointer<T>` owns one object, and a `WeakPointer<T>` is a checked stored reference to it. Both stay on the thread that made the object. `ConcurrentUniquePointer<T>` and `ConcurrentWeakPointer<T>` are the pair for an object that several threads share, locked for each use unless created `lockFree:` ([03](03-handles-and-objects.md#objects-shared-across-threads-concurrentuniquepointert)).
- A **`Sendable`** type is one whose values may reach another thread. The compiler derives it from what the type holds, every `Synchronized` type is one, and a type can opt out with `~Sendable` or promise it with `unsafe Sendable` ([07](07-concurrency.md#what-may-cross-threads-sendable)).
- A thread runs Rayo code inside a **section**, and a long-lived thread body leaves its section at a **checkpoint**, between units of work. Memory made unreachable while a view may still read it is **retired**, and reclaimed only once every thread has been outside a section since ([08](08-grace-periods-and-checkpoints.md#grace-periods-how-deferred-memory-is-reclaimed)). A **parked** thread is blocked in a wait, such as on a queue or a condition variable.

Each case describes what the code is trying to do, and then lists its pass criteria:

- **Must accept:** the spec must let you write this. The tier it lands in decides the verdict (below).
- **Must hold:** a property the spec's rules must have.
- Other bullets are requirements the solution must meet, or questions your report answers (**state**, **show**, **define**, **name**).

For every case, report the **tier** the natural solution lands in, and one verdict:

| Verdict | Meaning |
| --- | --- |
| **Solved** | The pattern is written directly, in the cheapest tier that can reasonably check it, and it meets every pass criterion. |
| **Solved with cost** | It's expressible, but only in a more expensive tier than it should need (a run-time check the compiler could have proven, a copy, a restructuring), or with more ceremony than the same code in C++, C# or Swift. Name the cost. |
| **Forced unsafe** | A pattern that isn't inherently unsafe can only be written with `unsafe`. **This counts as a failure.** Cases marked *(inherently unsafe)* are exempt: there `unsafe` is expected, and the question is how small and auditable it can be. |
| **Forbidden** | The pattern can't be written at all, even with `unsafe`. Always a failure. |
| **Unsound** | Code the spec accepts as safe produces a data race, use-after-free, dangling view or other undefined behavior, with C and `unsafe` code that keep exactly what the spec asks of them ([09](09-c-interop.md#what-c-must-uphold), [11](11-errors-and-safety.md#unsafe-code)). It breaks a step of [15](15-soundness.md). **Always the most severe finding.** |

Writing `copy` where the code makes a copy isn't ceremony: Rayo requires copies to be written out ([14](14-decisions.md) D14). An extra copy that C++, C# or Swift wouldn't make is a cost.

For each verdict, include the Rayo code you wrote (short) and the spec sections it relies on. A case can't be marked Solved by pointing at a sentence in the spec: the code has to type-check under the rules as written.

Beyond the listed cases, the validator should hunt for **any other reasonable systems pattern the spec forbids or forces into `unsafe`**, and report it as a new case.

---

## A. Borrowed and stored references

Borrows are checked statically within a function, with no lifetime parameters, and stored references move to the dynamic tier (weak pointers, `Slice`, `Handle`). These cases probe both sides of that line: code that should stay free and static, and code that needs stored references but shouldn't need `unsafe`.

### A1 · Views into a buffer the function owns (also A4)

A function loads a large text into an owned `String` and splits it into tokens whose text views the source, as a tokenizer does. The tokens are collected into a list, filtered, and handed on.

- **Must accept** tokens that view the source without copying text, in a token list that lives as long as the function needs it.

### A2 · Collecting views through helpers, loops and callbacks (also A15, part of A24)

Code collects views of a text into a list it owns, and uses the list afterwards. It does so through a helper, a loop and a callback:

```swift
func splitLines(_ text: StringView, into out: mutable List<StringView>) { ... }

splitLines(source.view, into: &lines)                           // the helper appends to the caller's list
for entry in table.entries { names.append(entry.name.view) }   // a loop over a collection
forEachLine(src.view) { line in lines.append(copy line) }      // a callback
print(lines.count)
```

- **Must accept** all three, and a user-defined sequence, such as a lexer used as a `for` sequence, whose elements are collected the same way, with no fallback to index loops.
- In the helper and the callback, the dependency is created *inside the callee*, and the caller must learn about it with no annotation, or with a small checked one.
- **Must accept** a quicksort without recursion that keeps its pending ranges as spans in a worklist, starting with `work.append(&data[0..<n])` and popping with `while var s = work.popLast()`, with `data` untouchable until `work` is dead.
- **Must accept**, with no `where` clause, `lexer.lex(into: &tokens)` and `fill(&keys, &values)` over two `List<StringView>`s, each list used afterwards: a list takes on what the other arguments view, not the arguments themselves.
- **Must accept** `t.map { copy $0.text }` over a `Span<Token>` and `entries.map { $0.name.view }`, each result used after the call, and `for row in rows { spans.append(row.span) }` over a `List<[4 of Float]>`, with `spans` used after the loop.
- **Must accept** `copyAll(from: src, into: &dst)` over two `List<StringView>`s, with a checked annotation, then `src` changed while `dst`'s views are used.

### A3 · A result that depends on only one argument

A lookup takes a key that views one buffer and returns a view into another, and the code then changes the first buffer while it still uses the result. A parser does this when it looks a token's text up in a symbol table, then advances the lexer:

```swift
let tok = lexer.peek()                         // view into lexer's buffer
let entry = symbols.find(tok.text)             // view into symbols; key only used for lookup
lexer.advance()                                // mutates lexer
use(entry)
```

- **Must accept** this sequence, possibly with a small annotation on `find` that the compiler checks. If the spec's answer is "restructure", count it as Solved with cost, and state how common the pattern is in parsers and lookups.
- **Must accept** a struct holding a view of a request and a view of a table, passed to a lookup whose result depends only on the table, then the request replaced while the result is used.
- **Must accept** ordinary helpers with no annotation, such as `span.min(by: …)`, `max(a.view, b.view)`, or `grid.row(y + 1)`, whose results depend only on what they view, never on a scalar argument such as `y + 1`, and `func labelOf(_ d: any Named) -> StringView { d.label() }`, whose result is used after its statement.

### A5 · Long-lived views into a long-lived buffer

A large buffer is loaded once, and many long-lived structs hold views of ranges inside it for as long as it lives, as the components of a loaded level hold views of its package. Separately, code keeps `Slice<T>`s into a lockable `ConcurrentUniquePointer<Blob>` it edits, replaces the whole blob with a shorter one, and reads through an old slice.

- **Must accept** storing those references in long-lived structs, without copying the data. Name the cost of whatever replaces the views (offsets, a shared owner): run-time checks, and bytes per reference where the spec fixes a layout.
- **Must accept** reads through slices that still fit, without re-creating them.

### A6 · A mutable cursor re-targeted down a tree

`struct Node(var value: Int, var children: List<Box<Node>>)`. Walk from the root down a path chosen at run time, keeping one mutable cursor, then insert a child at the end of the path. In C++:

```cpp
Node* cur = &root;
for (int i : path) cur = cur->children[i].get();    // re-target the cursor to a child
cur->children.push_back(std::make_unique<Node>());
```

- **Must accept** a loop that re-targets the mutable cursor to a child each iteration.
- **Must accept** the same walk when the children are `List<UniquePointer<Node>>` and the tree is 10,000 levels deep, without a run-time mark held per level.

### A7 · Accessors, user subscripts and columns (also part of A24)

Code needs two *computed* projections of one value (`modify` accessors, [02](02-views-and-dependencies.md#projections-read-and-modify-accessors)), not stored fields, mutably at once:

```swift
var p = &world.physics     // a modify accessor
var r = &world.render      // another one, on the same world
step(&p, &r)
```

- State whether this compiles. If it doesn't, give the idiom and its cost. Rust has the same limitation, so "same as Rust, and here is the workaround" is an acceptable answer.
- **Must accept** a user container, such as a ring buffer over raw memory, whose `modify` subscript yields an element, and a function that takes the container `mutable` and returns a view of that element.
- **Must accept** an `SoA<T>` column, a view of the buffer that holds one field of `T`, taken as a `MutableSpan` with `var lives = &particles.life` and moved into a struct of views, into a closure, or into an `owned` parameter.
- **Must accept** optional chains through projections: `node.next = nil` and `node.next.take()` through a property that yields a stored optional field, `pool[a]?.hp = copy pool[b]!.hp`, `world.enemies[h]?.hp -= reinforce(&world.enemies)`, `let hp = copy target?.hp`, and `if let c = h?.cell { use(c.tag.span) }`.

### A8 · A graph with cross-links, freed all at once

A graph of many nodes, each with links to its neighbors and a parent link set during a search, is built, searched and freed all at once, as a navigation graph is per level. In C++:

```cpp
struct NavNode {
    Vec3 pos;
    std::vector<NavNode*> neighbors;
    NavNode* parent;                 // set during a search
};
```

- **Must accept** building the graph, a search over it such as A*, and freeing it all at once.
- The cost of the replacement (indices vs. pointers: size and checks) must be stated.

### A9 · A value that owns a buffer and views into it (self-referential)

A value owns some bytes and wants fast views of a table inside them, as a font owns its file and views its glyph table. In C++:

```cpp
struct Font {
    std::vector<uint8_t> file;              // owns the bytes
    std::span<const GlyphRecord> glyphs;    // points into 'file'
};
```

- State the idiom. An offset-based answer is acceptable if its cost is named.

### A10 · Lending iterator over mutable chunks

Iterate `MutableSpan<Float>` chunks of 64 elements from a list and pass each chunk to a kernel that mutates it. In Rust:

```rust
for chunk in data.chunks_mut(64) { simd_kernel(chunk); }
```

- **Must accept** safe code with no copies.

### A11 · Locks: guards and closures

Acquire a lock, get a view of the protected data, use it across several statements, and release the lock at scope end, without a closure. In Rust:

```rust
{
    let mut reg = REGISTRY.lock().unwrap();   // the guard
    let list = &mut reg.entries;              // a view of the protected data
    list.push(e);
    list.sort();
}                                             // unlocked here
```

Separately, `mutex.lock { data in … }` returns a value computed from the protected data.

- **Must accept** the guard as a scoped value, or state the closure-only cost.
- **Must accept** a helper that returns the guard, as a method of a struct holding the mutex or as a free function over a global mutex, and a service-locator function that returns the view a global `Once` lends.
- **Must accept** the closure form returning an owned result, generically.
- **Must accept** a guard moved into a closure, as in `let h = Handler(onClick: { [move g] in print(g.value.count) })`, and `let n = total({ [move g] in g.value.count })` followed by taking the same lock again.
- **Must accept** two `Slice`s of one lockable blob read at once on one thread, and a concurrent object's `read` nested in its own `read`, even while a writer waits.
- **Must accept** a lock-free concurrent object whose value is a struct of `Synchronized` fields and concurrent owners, such as a log `Mutex` and an audio mixer, used from any thread.

### A12 · Sorting with a comparator that borrows

Sort a list of handles by a key the comparator reads from the pool they index, such as each object's distance to a point. In C++:

```cpp
std::sort(targets.begin(), targets.end(), [&](Handle a, Handle b) {
    return dist(enemies[a].pos, player) < dist(enemies[b].pos, player);
});
```

- **Must accept** a comparator closure that borrows the pool and isn't allocated.

### A13 · Interned strings

An interner returns ids that are cheap to compare and to store in other values, and that resolve back to text.

- **Must accept** storing interned ids in pool elements, comparing them in O(1), and getting the text for logging.
- State what replaces Rust's `&'static str` / `&'interner str`.

### A14 · Callbacks that need context

A callback registered now must mutate program state when it fires later, as a UI button's "on click" does. Elsewhere, a factory function builds and returns a closure that owns its captures.

- **Must accept** a safe idiom, spelled out, such as a handle plus an event queue, or a context passed at fire time.
- **Must accept** the factory returning its closure as a `Closure<() -> Int>`.
- **Must accept** a local holding a function value made from a literal, such as `let put: (mutable List<StringView>) -> Void = { … }` or `let h = Handler(onClick: { … })`, used for the rest of its scope; a named function or operator stored as a function value and called long after; and a literal that captures nothing as a parameter's default or as a returned plain function type.
- **Must accept** a local tokenizer closure that advances a captured position and returns views of a shared source, with two tokens live at once.
- **Must accept** a `mutating` closure local that owns a moved-in list, passed to a function taking `consuming () -> Void` and then called again, its list destroyed once.
- **Must accept** a closure kept by its concrete type in a generic struct, as `let r = wrap({ [move s] in s.count })` does, with its field passed to a function that takes a plain function type.
- **Must accept** `each(enemies.span) { e in if e.hp < 10 { low.append(tag.view) } }` through a `some mutating (Enemy) -> Void` parameter, with `low` depending only on `tag` afterwards.

### A17 · Remembering what a function saw

A function scans a local list of candidates and wants to keep the ones it picked for later calls.

- **Must accept** keeping them as owned values, such as a `List<T>` of copies, or as `Handle`s.

### A19 · Enumerating while mutating, in parallel

A job system's parallel loop hands its body each element of a collection together with the element's index:

```swift
grid.cells.forEachIndexedInParallel { i, cell in cell.value = f(i) }
```

- **Must accept** with the true index in every call and no copy of the collection. Show how the library's splitting keeps each part's starting index.
- **Must accept** the sequential form over a temporary, `for (i, var e) in &makeItems().enumerated()`, which changes its elements, with the true index in every iteration and no copy of the temporary.

### A20 · Mutating through a list of existential views

A function collects mutable views of values of three different types that conform to one protocol into a local list, then calls a mutating requirement through each. In C++:

```cpp
Damageable* targets[] = { &player, &boss, &crate };   // three different types
for (Damageable* t : targets) t->takeDamage(10);
```

- **Must accept** with no boxing and no allocation beyond the list.

---

## B. Object graphs

### B1 · A hierarchy updated parent-first, with reparenting

A tree of many nodes with parent handles and child lists is updated parent-first, and a node can be reparented during the same update, as a scene graph's transforms are.

- **Must accept** O(n) update, reparenting, and cycle prevention (reparenting a node under its own descendant must be detected).

### B2 · Two arguments that may be one value

A function mutates two values that may be the same one, as `attack(attacker, target)` does when an entity damages itself. In C++:

```cpp
void attack(Entity& attacker, Entity& target) {
    attacker.stamina -= 10;
    target.hp -= attacker.power;
}
attack(e, e);    // both parameters name one entity
```

- **Must accept** an idiom that handles the aliasing case correctly and explicitly.

### B3 · A coroutine waiting on an object that is destroyed

A `task` (a coroutine its owner steps explicitly, [07](07-concurrency.md#semantics)) waits on a condition about an object, such as `until { [copy target] game in game.enemies[target] == nil }`, when another part of the program destroys the object and a new one reuses its slot.

- **Must hold:** the task observes that the object is gone, and doesn't observe the new occupant.

### B4 · Event dispatch

Parts of a program publish events, and handlers in other parts mutate shared state in response. Handlers can publish further events.

- **Must accept** a design with no global mutable state and no stored mutable borrow of anything.
- It must be deterministic in order.
- Handler recursion (an event published while dispatching) must have defined behavior.

### B5 · Moving a value between containers

A move-only value, such as an item that owns a `String` description, moves from one container to another.

- **Must accept** moving it without cloning. If the values live in a pool and the containers hold handles, show that instead, and state which is idiomatic.
- **Must accept** the same moves through `replace(&slot, with:)`, `swap`, an `Optional` field's `take()` or `remove(at:)`.
- **Must accept** moving a field out of an owned local, or out of a call result as in `give(makeLoot().item)`, whose type has no `deinit`, with the rest destroyed at the scope's or statement's end; and a `deinit` handing a field, or a `List` in its enum's own payload, to another owner.
- **Must accept** `consuming func close() throws(IoError)` on a file whose `deinit` closes it, closing it once on every path, and a wrapper's `consuming func intoItems() -> List<T>` that moves its field out.
- **Must accept** `builder.finish(builder.count)` for a `consuming` `finish`, and `adopt(list, list.count)` for an `owned` first parameter.
- **Must accept** matching a temporary whose type has a `deinit`, as in `when connect().state { .open(let buf) -> … }`, and changing a payload in place, as in `when connect() { .open(var b) -> b.append(0) … }`.
- **Must accept** `for s in consume tags { names.append(s) }` over an inline array of `String`s, with a `break`.
- **Must accept** `let e = if c { enemies[0] } else { makeEnemy() }` and `let b = attr ?? Bounds(lo: 0, hi: 1)`, each borrowing on one path and owning on the other, used in later statements.

### B7 · Queries over optional components

Entities have optional components of many types. A query needs every entity with two given components but not a third, with dense iteration.

- **Must accept** an ECS-style library written in Rayo with no macros, using reflection or generics, iterating in parallel through a job system with statically checked disjointness between component storages.

---

## C. Concurrency

std provides threads and structured concurrency, checked by the language's ordinary rules ([07](07-concurrency.md), [14](14-decisions.md) D9). Where a case forks work, assume std's shapes in 07, which a job system of a program's own would share:

- `join` takes two `@sendable` closures, each of which may write what it captures, and returns when both are done. `@sendable` means every capture must be `Sendable`, whether borrowed or owned, and `join` also requires what the closures return or throw to be `Sendable` ([07](07-concurrency.md#the-librarys-promise)).
- `forEachInParallel` runs a non-`mutating` `@sendable (mutable Element) -> Void` body over a collection's elements.
- `Thread.scope { s in s.spawn { … } }` starts threads that may borrow the caller's locals, and joins them when the block ends.

Work handed to other threads this way is **lent work** ([07](07-concurrency.md#lending-work-to-other-threads)). The library's `unsafe` core, its scheduling and its error policy are its own design. The cases check that its safe uses can be written, and that its own `unsafe` promise is small and easy to state.

### C1 · Parallel scatter into shared data

In a parallel loop, each element adds a value to one cell of a shared grid, and many elements may pick the same cell. In C++:

```cpp
parallel_for(particles, [&](const Particle& p) {
    grid[cellOf(p.pos)] += p.mass;    // many threads write one grid
});
```

- **Must accept** a safe idiom (atomics, per-thread grids plus a merge, or sort-then-bucket).

### C2 · Disjoint writes to one value from several threads (also C16)

Two closures work on one `world`: one writes `world.velocities`, and the other reads `world.positions`. Separately, inside `Thread.scope`, the block spawns one thread per part of the work while it works too: one thread writes `world.bodies`, another writes `world.ai` and reads `world.perception`, and the block writes `world.audio`. A helper function takes the scope `mutable` and spawns two more threads over places its caller lends it.

- **Must accept** `join` with the two closures, and all of the scoped threads, with no copies of the world and no `unsafe` outside std. Once the scope returns, every place the spawns borrowed is free again.

### C3 · Two threads on alternate buffers

One thread reads snapshot N while another writes snapshot N+1, concurrently and for longer than any one call, as a renderer and a simulation do.

- **Must accept** a safe idiom. State what the language checks and what only the library enforces.

### C5 · Nested parallelism, and threads that wait (also C11)

A parallel loop's body calls a function that itself runs a parallel loop through the same library. The library avoids deadlock and oversubscription by running inner work on the threads already waiting in its joins, as work stealing does, including a thread that holds a lock while it waits. Separately, a thread started with `Thread.start` blocks in `Future.wait()` on a future another thread completes.

- **Must hold:** the inner call is checked by the same rules as the outer one, and the language adds no rule for nesting.
- **Must accept** a library that runs inner work on the threads already waiting in its joins. State what the language requires of work a library runs on a thread that is waiting in its own join.
- **Must hold:** `Future.wait()` runs no other code inline, except, as a checkpoint, its own thread's queued `deinit`s ([08](08-grace-periods-and-checkpoints.md#deinits-queued-to-a-thread)).
- State what happens when lent work run on a waiting thread takes a lock that thread holds, so a library knows what running unrelated work inline costs.

### C6 · Allocation inside lent work

Each call of a parallel loop's body appends to a `List` it owns locally, and to a `List` owned by the element it was given.

- **Must accept** with defined thread-safety for the allocators involved. A scratch arena that gives each thread its own block to allocate from, used from many threads, must be well-defined.
- **Must accept** the lending thread using and freeing, after the join, what lent work allocated through an allocator that keeps state per thread.
- **Must accept** generic code that runs a parallel loop over `T` elements with a `(mutable T) -> Void` body, constrained only by `T: Sendable` and what the element operations need.

### C7 · Panic and errors in lent work

A closure panics on a worker thread in the middle of a parallel loop. Separately, both closures of a `join` and several calls of a parallel loop's body throw.

- Define what happens to the other threads, the process, and the report.
- **Must hold:** the library can propagate one error after the join, by its own policy, and destroy the others, with no double free and no leak.

### C10 · Resetting a shared arena while other threads allocate from it

An arena shared by several threads is reset by one of them while two others are in the middle of allocating from it, and a third is creating a concurrent object in it.

- Each allocation racing the reset is ordered before it, and goes stale, or after it, and stays valid; state the rule that orders it.
- The reset must not wait for the other threads.

### C12 · A job and thread library written in Rayo (also C13, C15)

A team writes its own job system in Rayo: worker threads, `join`, and a parallel loop over a collection type it can split into disjoint parts. It writes its workers twice, once over `Runtime.startThread` and once over the platform's thread API through `import c`, with a `@c func` start routine. Workers run bodies of type `Closure<consuming @sendable @entry () -> Void>` from a list, and one worker parks on a queue it owns between jobs. The list, the queue and the bodies' captures were created while an arena was the current allocator, and the arena is reset while the workers are parked.

- **Must accept** the job system with its unverified part as small as possible, and state what it promises. The workers over `Runtime.startThread` need no `unsafe`, and those over the C API no `unsafe` beyond the C thread call.
- **Must accept** the parked workers, with their bodies' checkpoints taking effect and retired memory reclaimed while they wait.

### C14 · A single-consumer queue whose consumer moves

A library's global single-producer, single-consumer queue feeds one consumer thread, and later a C library calls the consuming callback from a thread of its own instead.

- **Must accept** the consumer changing threads, and a queue whose single side is proven statically, such as a `Channel`'s `Receiver`, paying nothing for a check.

### C17 · Objects that one thread uses, and objects that many do

A program has three kinds of state:

1. a tree with parent pointers, used only on one thread, such as a UI widget tree;
2. an object that several threads all change, such as an audio mixer;
3. the id of a C resource, a `UInt32` that is valid only on one thread, such as an OpenGL texture's.

- **Must accept** the tree with no synchronization on any access, the shared object with every access marked as a lock at the call and no wrapper type around it, and the resource id as a type that stays on its thread although its only field is an integer.

---

## M. Memory

### M1 · Keeping short-lived results in long-lived state

Code builds a `List` in a scratch arena that is reset regularly, such as once per frame, and keeps what it needs past the reset in a long-lived struct.

- **Must accept** `using allocator = .system { world.results = scratch.clone() }` for a `List<String>` built in the arena, then the reset and `world.results.append(r)`: the clone's buffers, its elements' included, come from `.system`.

### M2 · Freeing a large set of objects at once

Every value of one phase of a program, such as a level's entities, graph nodes and strings, is freed at once, and the cost on the thread that frees them must not grow with their number. They live in one heap, some of them objects, some pinned for C, and the heap is unregistered while weak pointers to them are still stored elsewhere.

- **Must accept** an idiom whose cost on the freeing thread doesn't depend on how many objects and values the heap holds. State which thread runs the objects' `deinit`s, and when ([03](03-handles-and-objects.md#objects-in-arenas-and-other-allocators)).

### M3 · Out of memory

An allocator is exhausted in the middle of a batch of allocations, such as a streaming load under a hard memory limit.

- **Must accept** detecting that and backing off gracefully (evict, retry), without a panic, in a collection built on what the language provides, such as the builtin `SoA`'s fallible growth or a user collection over `allocateRaw` and `reallocateRaw` ([06](06-memory-and-allocators.md#allocation-failure)).
- State what the language's allocating operations do on failure by default.

### M4 · Memory valid until an external event

Code writes a large batch of data into memory that a C API mapped: a pointer with a stated alignment, valid until an event that follows an action the program takes, such as a GPU fence that signals after the program submits the batch.

- **Must accept** safe Rayo code writing through a view whose validity is enforced in every build.
- The unsafe surface must be a small wrapper.

### M5 · Memory budgets for one part of a program

One part of a program may use at most a fixed amount of memory. Its budget wrapper sits over the system heap, or over an arena that is reset while that part still holds lists allocated through the wrapper.

- Exceeding the budget must fail allocations in that part only, and a tracking allocator must be able to attribute the usage.

---

## E. C interop

Every crossing between Rayo and C is unsafe by definition ([09](09-c-interop.md), [14](14-decisions.md) D13), so these cases are exempt from **Forced unsafe** on the C side. They check two things: the mapping is precise enough to bind real C APIs, and the Rayo wrapper's `unsafe` part stays small, with obligations that are easy to state and keep.

### E1 · C holding pointers into Rayo memory

A C library stores a `void* user` per registered item and calls a callback on its own threads with two of those pointers, as a physics library's contact callback does. Some items are elements of a `StablePool`, which the program later replaces whole (`pool = StablePool()`), and some are objects allocated in an arena that is later reset. Separately, a global `let` `StablePool`, which is initialized at startup, never placed in static data ([10](10-compile-time.md#consts-that-reach-run-time)), has one of its elements pinned for C.

- **Must accept** an idiom whose `unsafe` part is only the C calls. State what the Rayo side must provide: stable addresses of whatever `user` points to, and thread safety.
- **Must hold:** C's address stays valid for as long as its pin lives, and replacing the pool or resetting the arena doesn't run the element's `deinit` before C is done with it. The global element's address is valid for the whole run.
- State what C sees when Rayo code assigns a new value to a pinned element.
- **Must accept** moving the `Pin` of a `Sendable` `StablePool` element to an I/O completion thread that drops it there.

### E2 · C types with unusual layouts (also A22)

Code imports C structs with bitfields, anonymous unions, flexible array members, packed structs, and `enum`s with explicit negative values, and uses them from safe code, some from several threads at once:

```c
struct E {
    /* ... */
    union { float f; uint32_t u; };   // anonymous union
};

#pragma pack(1)
struct R {
    uint8_t  tag;
    uint32_t vals[4];                 // at offset 1
};
```

- **Must accept** each imported with its exact layout; reading either member of a union of same-size plain-data members, and reading a file header that contains such a union as plain bytes; a C enum the header doesn't declare closed holding any value of its underlying type, including in a `@safe` module that matches it with `when`, with no undefined behavior.
- **Must accept** imported structs under the borrow rules: union members read and written by value, and two closures of one `join` writing bitfields in different C memory locations of one struct, or a bitfield and a neighboring field.
- **Must accept** reflection, serialization and `SoA` over an imported struct with bitfields, and a `@packed` struct conforming to a protocol whose `read`/`modify` property its under-aligned field provides, used from generic code.

### E4 · Exporting data and functions to C callers

Code in another language binds to Rayo through its generated C header: it reads a `List` of structs and calls Rayo functions with strings.

- The generated header must be enough to bind to.
- **Must accept** an idiom for reading the list whose obligations on the caller's side are easy to state and keep, even when the list's storage came from an arena that is later reset or a heap that is later unregistered, and when the runtime reclaims memory on its own.
- The caller calls back an `@export` function that takes a span and a weak pointer to the list, whose body appends to the list. State what the caller may pass as the span.
- **Must accept** an `@export` function that builds a `String` in the current thread's scratch arena and gives the caller an owner that stays valid until the caller frees it through the header's function.

### E5 · SIMD values across the boundary

Call a C function that takes a vector type such as `__m128` or `float32x4_t` by value.

- **Must accept** `Simd<Float, 4>` passed directly, with a defined ABI mapping.

### E6 · Mistyped references from C

C holds references to Rayo objects of different types as `uint64_t`s, and may pass the wrong one back to an `@export` function.

- **Must accept** an entry point that defends itself against that mistake, so the wrong object is never accessed as the other type, in any build, with no `unsafe` in the Rayo code.
- **Must accept** C holding references to objects of different types as `uint64_t` and passing them to one Rayo function that takes any object conforming to a protocol.
- **Must accept** a `@c func` callback taking two `ConcurrentWeakPointer<T>`s, registered with a C library whose callback type takes two `uint64_t`s and that calls it on its own threads, and the same with `WeakPointer<T>` for a library that calls back on the thread that drives it. State what the C library must uphold in each.
- **Must accept** `Handle` bits that C passes back as a `void* user` which addresses nothing, converted back only by `unsafe` code.

### E7 · C code that needs a large stack

A C library's function recurses deeply, and a plugin's callback is documented to need 1 MiB of stack.

- **Must accept** calling each, within C's obligations, by declaring its need where the function or the pointer type is declared.

---

## F. Performance

### F1 · Vector math in unoptimized builds

A loop over many values does vector arithmetic, such as `pos += vel * dt; vel = lerp(...)`.

- **Must accept** unoptimized code with no function call per operation and no hidden check beyond bounds checks ([12](12-compilation-model.md#runtime-costs)).
- **Must accept** generic vector code over `T: VectorSpace` whose requirement calls reach `@inline` operators, each running in place in every build, and `@inline` functions that call each other in a cycle through a generic witness.

### F2 · Generic code size

A generic type such as `List<T>` is instantiated for hundreds of element types.

- State the code-size strategy and its compile-time cost.
- State whether shared (non-monomorphized) instantiation is possible.

### F3 · Many types behind one interface

Many types that conform to one protocol are run each iteration through the protocol, as an engine's render passes are.

- **Must hold:** no allocation per iteration and no hidden boxing, and the dispatch cost is visible in source.
- **Must accept** passing each `mutable any P`, or each `Box<any P>` element's `&b.value`, to a generic `func run<T: P>(_ x: mutable T, …)`. State how that call runs, given that generics are monomorphized, and its code-size cost.

### F4 · Bounds checks in hot loops

A kernel indexes `src[i + k]` inside a nested loop.

- Show how to reach check-free code: safe if possible, `unchecked` if not, with the audit surface stated.

### F5 · Bit-identical results on every target

A computation must give bit-identical results on every machine, as a lockstep simulation does when it compares a hash of its state across machines with different platforms and compilers. It uses `Float` and `Simd` math with `a * b + c` patterns, square roots and conversions, and calls whose arguments have side effects, such as `spawn(at: rng.next(), heading: rng.next())`.

- **Must accept** bit-identical state on every target, under every toolchain and in every build profile, from the language's rules alone. Name the rule that fixes each result.
- State what the program must avoid or supply itself to stay deterministic, such as its own `sin`.

### F6 · Integer and float edge cases

A hash function divides by a value read from a file, negates and divides `Int.min`, and shifts by a count computed at run time that can reach the bit width. It also converts a `Double` read from the file to `Int`, NaN included, or to a `Float` out of its range, converts a `UInt` count to `Int32`, and shifts negative values and `Int.max` left.

- Every result must be defined in every build, a value or a panic, never undefined behavior, and the cost in `ship` ([11](11-errors-and-safety.md#build-profiles)) stated.

---

## G. Hot reload: a tool the language must not rule out

A hot reloader swaps code and migrates live state while a program runs. It is a tool built on a runtime and toolchain layer that the spec doesn't define ([14](14-decisions.md) D12), so these cases don't ask how it works. They check that the language keeps it possible: each names language properties a reloader would build on.

- **Solved** means every property the case names holds in the spec.
- A rule of the spec that breaks one, such as a way for safe code to keep the address of a value it doesn't own, is the finding.

### G1 · Changing a type while values of it are alive

A field with a default is added to a struct while many values of it are alive, in a pool inside an object that `main` owns.

- **Must hold:** safe code can't learn a value's address, only immortal data's, unless `unsafe` code or C gives it a raw pointer. Its stored links are handles, weak pointers, owners, `Slice`s, `Pin`s, `RawAllocation`s, `Allocator` ids, `StaticSpan`s and `StaticString`s, `String`s that still use a literal's bytes, `Closure`s and `@c` pointers, which name code, and raw pointers, which only `unsafe` code or C makes.
- **Must hold:** at a checkpoint a thread holds no borrow and no dynamic access, except what a qualifying parking wait or entry call borrows under the path rule ([08](08-grace-periods-and-checkpoints.md#what-a-wait-may-borrow)).
- **Must hold:** a type's fields, their layout and their defaults are known to the compiler, and readable through reflection ([10](10-compile-time.md)).

### G3 · What C holds

C holds `user` pointers to pinned elements and a `@c` callback pointer, as in E1, and code in another language binds to a generated header that contains a `@c` struct.

- **Must hold:** every address C can hold is visible in the program: a `Pin`, a `RawAllocation`, such as a leaked box's, a `@c` function pointer, an `@export` symbol, a `StaticSpan` or `StaticString`, a `Span`, `MutableSpan` or `StringView` an exported or `@c` function returns, a `List`, `String` or `TrailingArray` returned to C ([09](09-c-interop.md#c-representations)), or anything `unsafe` code passed to C. A leaked object crosses as its weak pointer's bits, not an address. Every layout C sees is one that a generated header or C's own header declares.

### G4 · Suspended code

Tasks in a `TaskSet` are suspended, and a `Thread.loop` thread is parked waiting for its next item.

- **Must hold:** a task suspends only at `await`, holding no borrow and no dynamic access there; a thread leaves its section only at a checkpoint or by returning to depth zero, holding no borrow and no dynamic access there except what a qualifying wait or entry call borrows under the path rule ([07](07-concurrency.md#semantics), [08](08-grace-periods-and-checkpoints.md#what-a-wait-may-borrow)).

---

## H. Compile time and reflection

### H1 · Loading data written by older versions of its types

Load data written by an older version of a program's types, as a save game from version 3 is loaded into version 7, or as a hot reload carries live values into new code. Fields were renamed, added, retyped, and removed across versions, and enum cases removed.

- **Must accept** a reflection-driven loader plus per-type migration hooks, written as a library without a macro system or any language feature specific to loading.
- **Must accept** a migration that rebuilds a value field by field from an owned old one, `T.construct { static field in consume old[field] }`, for a type with no `deinit` that holds `List`s.

### H3 · Registration without macros

Every type of some kind must be registered in a global registry at startup, as C++ does with static-init macros.

- **Must accept** an idiom with no unsynchronized global state.

### H4 · Generated types

Three kinds of generated types are needed:

1. For every struct with fields marked by an attribute, such as `@Replicated`, a library needs a `Delta<T>` holding one optional per marked field, under the field's own name, plus a generic `diff` and `apply`, and it serializes each delta.
2. A library needs `Overrides<T>`, with every field optional.
3. A library needs one enum with a case per type in another module that conforms to a protocol.

- **Must accept** each written once, as library code with no macros, no external generator and no per-type hand-written code, serialization included. Concrete code names the generated members directly (`delta.hp`), and generic code reaches them through reflection.
- **Must hold:** `TypeInfo` and reflection see generated types as they see written ones.
- **Must accept** two closures of one `join` writing two generated fields of one `Delta<Enemy>`, and `struct Node(var pending: Delta<Node>)`.

---

## I. Systems patterns that must not be forbidden

Each of these is ordinary in C or C++. Report the tier and the ceremony next to the C++ version.

### I1 · Pointers between long-lived objects

A value points at another that outlives it, one part of a program holds pointers to three others, and two values point at each other and both mutate through the link. In C++:

```cpp
struct Camera;
struct Player { Camera* camera; Vec3 pos; };
struct Camera { Player* target; float zoom; };
```

- **Must accept** in safe code, without making either of the pair own the other.
- State the per-access cost, and whether it is avoidable where the compiler can see the target is alive.

### I2 · Intrusive doubly linked list

Link nodes embedded in objects, each object in two lists at once, with O(1) unlink given just the object. In C++:

```cpp
struct Link { Link* prev; Link* next; };
struct Enemy {
    Link active;      // in the "active" list
    Link inCell;      // in its grid cell's list
    // ...
};
void unlink(Link& l) { l.prev->next = l.next; l.next->prev = l.prev; }
```

- **Must accept** in safe code or with a small audited `unsafe` core.

### I3 · Re-entrant observer

An object notifies its listeners, and a listener calls back into the same object during the notification. In C++:

```cpp
void Door::open() {
    isOpen = true;
    for (Listener* l : listeners) l->onOpened(*this);   // a listener calls lock() on this door
}
```

- **Must accept** some safe way to write this.
- If the natural version panics at run time, the types involved must announce the panic, and the report names the idiomatic alternative.

### I4 · Global configuration and logging

A global configuration is read everywhere, including from lent work and worker threads, and edited while the program runs. A global logger is called from every thread at once.

- **Must accept** in safe code, with concurrency behavior that suits contention. Two threads logging at the same time must not panic.
- The cost of each access must be stated.
- **Must accept** as safe globals an inline array of 64 mutexes built without a 64-element literal, a struct of `Synchronized` fields, a `ConcurrentUniquePointer`, a `List<Mutex<Job>>`, and an array of `@sendable` `Closure`s.

### I5 · Waiter registered from the stack

A function declares a local `Waiter`, registers a pointer to it in a global wait list, blocks until signaled, and unregisters, as the Linux kernel's wait queues and many job systems do. In C++:

```cpp
void waitForJob() {
    Waiter w;                 // lives in this stack frame
    waitList.add(&w);         // a global list now points into the frame
    w.block();                // until another thread signals w
    waitList.remove(&w);      // forgetting this leaves the list dangling
}
```

- *(inherently unsafe, or dynamic)*: state which tier it lands in, and whether anything stops a forgotten unregister from dangling.

### I6 · Load-in-place data with pointer fixups

Read a blob from disk into memory, then patch relative offsets into pointers, so the blob's structs point into the blob itself. Use it in place with zero parsing. In C:

```c
struct Mesh { Vertex* verts; uint32_t count; };            // on disk, 'verts' holds an offset
mesh->verts = (Vertex*)(blob + (uintptr_t)mesh->verts);    // the fixup
```

- *(inherently unsafe at the fixup step)*: the fixup must be a small `unsafe` core, and *using* the loaded data must be safe code.

### I7 · Variable-sized struct

A header followed by N trailing elements in one allocation (C flexible array member), created and accessed in Rayo.

- **Must accept** with a safe accessor for the trailing elements.

### I8 · Tagged pointers and NaN-boxing

Pack a type tag into the low bits of an aligned pointer, or a pointer into a NaN's payload bits, as a VM's value type does.

- *(inherently unsafe)*: the `unsafe` surface must be one small type.

### I9 · Lock-free MPSC queue implementation

Implement a lock-free multi-producer, single-consumer queue, as std's `MpscQueue` could be, from atomics and raw memory.

- *(inherently unsafe)*: the spec must provide atomics with explicit orderings, and a way to conform the result to `Synchronized`.

### I10 · Placement construction into preallocated memory

Construct values in a caller-provided buffer, such as a ring buffer of commands with variable-sized entries, and destroy them in place.

- **Must accept** with a small `unsafe` core, or safely through a std type.

### I11 · Hand-written vtables and C-style inheritance

A `struct Base { const VTable* vt; }` prefix embedded as the first field of derived structs, cast between them, in a layout a C library requires:

```c
struct VTable { void (*update)(struct Base* self, float dt); };
struct Base   { const struct VTable* vt; };
struct Player { struct Base base; float hp; };      // Base is the first field

void player_update(struct Base* b, float dt) {
    struct Player* p = (struct Player*)b;           // the cast
    p->hp -= dt;
}
```

- *(inherently unsafe at the cast)*: Rayo's layout rule must guarantee the prefix, and the casts must be one wrapper.

### I12 · Type punning and bit reinterpretation

Reinterpret a `Float` as a `UInt32`, and view a `Span<UInt8>` as a span of a struct type, with checks for alignment and size.

- **Must hold:** a bit cast is safe from a padding-free `Pod` type to a `Pod` type of the same size ([04](04-types.md#plain-data-pod-and-bit-casts)), and the span reinterpretation is safe when checked.
- State which types qualify.

### I13 · Memory-mapped I/O / volatile access

Write to a device register or a device-visible, write-combined region, with the required volatile and ordering semantics.

- *(inherently unsafe)*: the spec must expose volatile loads and stores, and fences.

### I14 · Destruction deferred until an external event

A resource must not be freed until an external event, such as a GPU fence, has signaled, even though the program dropped its last reference earlier.

- **Must accept** deferred destruction tied to an external event, with no use-after-free possible in safe code.

---

## J. Ergonomics

### J1 · A state machine with timers

Write a state machine with five states, timers and transitions, such as an enemy's AI moving between idle, patrol, chase, attack and flee.

- The code must read like ordinary application code: no ownership ceremony beyond `mutable`, and at most one handle lookup per object per state.
- Compare its length to the same code in C#.

---

## K. Reclamation in practice

### K1 · A program that runs once

A command-line tool runs once. It starts threads, runs work on a job system, publishes shared settings through `Published`, destroys lock-free concurrent objects, and resets arenas.

- **Must accept** every construct.
- **Must hold:** the program can have retired memory reclaimed while it runs, not only at exit, through the runtime's reclaimer thread where there is one, or `Runtime.reclaim` calls it places. State which the solution relies on.
- State which thread runs retired values' `deinit`s, and when.

### K2 · A long-running server

An event-loop server handles requests on worker threads for weeks. Each worker has its own scratch arena, which it resets after each request, and connection handshakes are written as `task`s stepped by the event loop.

- **Must accept** per-request scratch memory, stepped tasks, and a time-based wait driven by the server's own clock.
- Retired memory must stay bounded as long as each worker returns to its event loop between requests, whether that loop is a C library's that calls Rayo back, or Rayo code, a library's `@entry` function included, that idles in `epoll_wait` or on a futex, and the runtime's reclaimer thread, or the program's own `Runtime.reclaim` calls, reclaim it.
- State what the `unsafe` call to `epoll_wait` promises about the event buffer it hands the kernel, and show a buffer that keeps that promise simply.
- **Must accept** as waits that let reclamation proceed: an `@entry` worker loop parking on a `Receiver` it owns; `@entry consuming func run()` parking on `self.inbox`; a thread parking on the `rx` of `var (tx, rx) = Channel<Job>.make(…)`; `if var r = &rx { r.waitPop() }` on an owned optional receiver; `results.append(rx.waitPop())` on owned locals; a `@parks` queue wait built from a `Mutex` and a `Condvar`; and `extern c parks func wait_input(_ ms: CInt) -> CInt` over inline C.
- **Must accept** `@entry mutating func run()` called on an engine in a local of the entry body, which the body uses afterwards; `using allocator = frameArena { while running { work(); frameArena.reset(); checkpoint } }`; and a wait inside a loop over a borrowed collection, as a wait that just blocks.
- **Must accept** in the handshake tasks `total += await next()` and `results[i] = await fetch(i)` on a task's own locals; `let s = await peek(); print(s[0].hp)`, where `peek` returns a view of the resume parameter's data; a `defer` live across an `await` that uses only the task's owned locals; and an `await` inside `using allocator = a { … }`.

### K3 · A real-time callback

A `@noalloc` callback with a real-time deadline, called by a C library on its own thread, reads a `Published` configuration, as an audio callback reads its mixer settings.

- **Must hold:** a callback that reads the configuration through `current`, taking no snapshot, never runs another thread's retired values' `deinit`s or frees, and never waits on reclamation.
- **Must accept** a `@noalloc` function that calls a DSP closure it takes as a `@noalloc (mutable MutableSpan<Float>) -> Void`, drops a `Closure<@noalloc () -> Void>` it owns, and calls a `@c noalloc` pointer a C plugin handed over.
- **Must accept** callbacks on the C library's thread that use a `@threadlocal` scratch buffer, which the thread's first entry initializes and its detach destroys. State what the first callback may allocate, and how a `@noalloc` callback avoids it.

### K4 · Cleanup at exit

A program retires a lock-free concurrent object whose `deinit` flushes a log file, then returns from `main` a millisecond later, before anything has reclaimed it.

- **Must hold:** the `deinit` runs before the process exits, whether a runtime thread or the program's own calls do reclamation.
- Define what happens when another thread is stuck in a section at exit, or C still holds a pin.
- **Must accept** without a panic a lock-free concurrent object owned by a `@threadlocal var` of the thread that runs `main`, whose `deinit` builds an interpolated `String` before it flushes, and a thread-bound object leaked to C whose `deinit` appends to a `List` it owns, destroyed when its thread's body returns.
