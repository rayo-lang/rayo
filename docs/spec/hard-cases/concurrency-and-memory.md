# Concurrency and memory

[Hard cases](../hard-cases.md)

## C. Concurrency

**std provides threads and structured concurrency, checked by the language's ordinary rules** ([07](../07-concurrency.md)). Where a case forks work, assume std's shapes in 07, which a job system of a program's own would share:

```swift
join({ … }, { … })                          // may run both closures at once, and returns when both are done
particles.forEachInParallel { p in … }      // runs the body over the elements, on many threads
Thread.scope { s in s.spawn { … } }         // starts threads that may borrow the caller's locals
```

- **`join`** takes two `@sendable` closures, each of which may write what it captures, and returns when both are done. `@sendable` means every capture must be `Sendable`, whether borrowed or owned, since only `Sendable` values reach another thread. `join` also requires what the closures return or throw to be `Sendable` ([07](../07-concurrency/thread-work.md#the-librarys-promise)).
- **`forEachInParallel`** runs a non-`mutating` `@sendable (mutable Element) -> Void` body over a collection's elements.
- **`Thread.scope`** starts threads that may borrow the caller's locals, and joins them when its block ends.

Work handed to other threads this way is **lent work** ([07](../07-concurrency/thread-work.md#lending-work-to-other-threads)). The library's `unsafe` core, its scheduling and its error policy are its own design. The cases check that its safe uses can be written, and that its own `unsafe` promise is small and easy to state.

### C1 · Parallel scatter into shared data

**In a parallel loop, each element adds a value to one cell of a shared grid, and many elements may pick the same cell.** In C++:

```cpp
parallel_for(particles, [&](const Particle& p) {
    grid[cellOf(p.pos)] += p.mass;    // many threads write one grid
});
```

Written this way, two threads may write one cell with nothing ordering the writes: a data race, which is undefined behavior ([13](../13-soundness.md#the-invariants)).

- **Must accept** a safe idiom (atomics, per-thread grids plus a merge, or sort-then-bucket).

### C2 · Disjoint writes to one value from several threads (also C16)

**Two closures work on one `world`: one writes `world.velocities`, and the other reads `world.positions`.** Separately, inside `Thread.scope`, the block spawns one thread per part of the work while it works too: one thread writes `world.bodies`, another writes `world.ai` and reads `world.perception`, and the block writes `world.audio`. A helper function takes the scope `mutable` and spawns two more threads over places its caller lends it.

- **Must accept** `join` with the two closures, and all of the scoped threads, with no copies of the world and no `unsafe` outside std. Once the scope returns, every place the spawns borrowed is free again.

### C3 · Two threads on alternate buffers

**One thread reads snapshot N while another writes snapshot N+1, concurrently and for longer than any one call**, as a renderer and a simulation do. A thread that outlives the call that started it owns its captures, and can't borrow ([07](../07-concurrency/thread-work.md#what-a-thread-can-share)).

- **Must accept** a safe idiom. State what the language checks and what only the library enforces.

### C5 · Nested parallelism, and threads that wait (also C11)

**A parallel loop's body calls a function that itself runs a parallel loop through the same library.** The library avoids deadlock and oversubscription by running inner work on the threads already waiting in its joins, as work stealing does, including a thread that holds a lock while it waits. Separately, a thread started with `Thread.start` blocks in `Future.wait()` on a future another thread completes.

- **Must hold:** the inner call is checked by the same rules as the outer one, and the language adds no rule for nesting.
- **Must accept** a library that runs inner work on the threads already waiting in its joins. State what the language requires of work a library runs on a thread that is waiting in its own join.
- **Must hold:** `Future.wait()` runs no other code inline.
- State what happens when lent work run on a waiting thread takes a lock that thread holds, so a library knows what running unrelated work inline costs.

### C6 · Allocation inside lent work

**Each call of a parallel loop's body appends to a `List` it owns locally, and to a `List` owned by the element it was given.** Either append may grow its list, through the allocator the list was built with, on whichever thread runs the call ([06](../06-memory-and-allocators/allocator-basics.md#the-current-allocator)).

- **Must accept** with defined thread-safety for the allocators involved. A scratch arena that gives each thread its own block to allocate from, used from many threads, must be well-defined.
- **Must accept** the lending thread using and freeing, after the join, what lent work allocated through an allocator that keeps state per thread.
- **Must accept** generic code that runs a parallel loop over `T` elements with a `(mutable T) -> Void` body, constrained only by `T: Sendable` and what the element operations need.

### C7 · Panic and errors in lent work

**A closure panics on a worker thread in the middle of a parallel loop.** Separately, both closures of a `join` and several calls of a parallel loop's body throw.

- Define what happens to the other threads, the process, and the report.
- **Must hold:** the library can propagate one error after the join, by its own policy, and destroy the others, with no double free and no leak.

### C10 · Resetting a shared arena while other threads allocate from it

**An arena shared by several threads is reset by one of them while two others are in the middle of allocating from it**, and a third is creating a `Shared` value in it. A reset frees everything the arena handed out at once, and no release may free memory that a view, on any thread, may still read ([06](../06-memory-and-allocators/arena-safety.md#what-a-reset-does)).

- Each allocation racing the reset is ordered before it, and goes stale, or after it, and stays valid; state the rule that orders it.
- The reset must not wait for the other threads. State what it does while another thread still uses the arena's memory.

### C12 · A job and thread library written in Rayo (also C13, C15)

**A team writes its own job system in Rayo**: worker threads, `join`, and a parallel loop over a collection type it can split into disjoint parts. The language builds in none of these: threads, locks and job systems are libraries, which the language gives its checking rules ([07](../07-concurrency.md)).

The team writes its workers twice, once over `Runtime.startThread` and once over the platform's thread API through `import c`, with a `@c func` start routine. Workers run bodies of type `Closure<consuming @sendable () -> Void>` from a list, and one worker parks on a queue it owns between jobs. The list, the queue and the bodies' captures were created while an arena was the current allocator, and the arena is reset while the workers are parked.

- **Must accept** the job system with its unverified part as small as possible, and state what it promises. The workers over `Runtime.startThread` need no `unsafe`, and those over the C API no `unsafe` beyond the C thread call.
- **Must accept** the parked workers. **Must hold:** the reset never frees memory a parked worker still uses; state what it does instead, and what each worker sees when it next uses what the arena held.

### C14 · A single-consumer queue whose consumer moves

**A library's global single-producer, single-consumer queue feeds one consumer thread**, and later a C library calls the consuming callback from a thread of its own instead. The queue's algorithm must never see two consumers at once, and must see successive ones in order ([07](../07-concurrency/synchronization.md#queues-and-channels)).

- **Must accept** the consumer changing threads, and a queue whose single side is proven statically, such as a `Channel`'s `Receiver`, paying nothing for a check.

### C17 · Objects that one thread uses, and objects that many do

**A program has three kinds of state, which differ in the threads that may use them:**

1. a tree with parent pointers, used only on one thread, such as a UI widget tree;
2. an object that several threads all change, such as an audio mixer;
3. the id of a C resource, a `UInt32` that is valid only on one thread, such as an OpenGL texture's.

- **Must accept** each of these:
    - the tree, with no synchronization on any access;
    - the shared object, with every access marked as a lock at the call, and its sharing and its lock written in its type;
    - the resource id, as a type that stays on its thread although its only field is an integer.

---

## M. Memory

**Every heap allocation goes through an allocator the code can name, and every release happens at a point the code shows** ([06](../06-memory-and-allocators.md)). These cases test that rule against the ways systems code manages memory.

### M1 · Keeping short-lived results in long-lived state

**Code builds a `List` in a scratch arena that is reset regularly, such as once per frame, and keeps what it needs past the reset in a long-lived struct.** A reset makes every value allocated from the arena before it stale ([06](../06-memory-and-allocators/arena-safety.md#what-a-reset-does)), so what is kept must be copied out first. Here `scratch` is a `List<String>` built in the arena:

```swift
using allocator = .system { world.results = scratch.clone() }   // clones the list while .system is the current allocator
frameArena.reset()                                              // resets the arena that built 'scratch'
world.results.append(r)                                         // grows the kept list after the reset
```

- **Must accept** the code above: the clone's buffers, its elements' included, come from `.system`.

### M2 · Freeing a large set of objects at once

**Every value of one phase of a program, such as a level's entities, graph nodes and strings, is freed at once**, and the cost on the thread that frees them must not grow with their number. They live in one heap, some of them objects, some pinned for C, and the heap is unregistered while weak pointers to them are still stored elsewhere.

- **Must accept** an idiom whose cost on the freeing thread doesn't depend on how many objects and values the heap holds. State which thread runs the objects' `deinit`s, and when ([03](../03-handles-and-objects.md#objects-in-arenas-and-other-allocators)).

### M3 · Out of memory

**An allocator is exhausted in the middle of a batch of allocations**, such as a streaming load under a hard memory limit.

- **Must accept** detecting that and backing off gracefully (evict, retry), without a panic, in a collection built on what the language provides, such as the builtin `SoA`'s fallible growth or a user collection over `allocateRaw` and `reallocateRaw` ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)).
- State what the language's allocating operations do on failure by default.

### M4 · Memory valid until an external event

**Code writes a large batch of data into memory that a C API mapped.** The API gives a pointer with a stated alignment, valid until an event that follows an action the program takes, such as a GPU fence that signals after the program submits the batch. Making a view from a raw pointer takes `unsafe`, since such a view carries no dependencies for the compiler to verify ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)).

- **Must accept** safe Rayo code writing through a view whose validity is enforced in every build.
- The unsafe surface must be a small wrapper.

### M5 · Memory budgets for one part of a program

**One part of a program may use at most a fixed amount of memory.** Its budget wrapper sits over the system heap, or over an arena that is reset while that part still holds lists allocated through the wrapper.

- Exceeding the budget must fail allocations in that part only, and a tracking allocator must be able to attribute the usage.

---
