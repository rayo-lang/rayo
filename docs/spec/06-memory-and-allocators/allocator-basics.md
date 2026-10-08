# Allocator values and defaults

[06 · Memory and allocators](../06-memory-and-allocators.md)

## Allocator values

**An `Allocator` is a copyable id that names a registered allocator implementation.** An owning container records the allocator its storage came from, and grows and frees through it. So the allocator isn't part of its type: a `List<Prop>` from `levelHeap` and one from `.system` are the same type.

**Every registered allocator is either `.system` or library code:**

- **`.system`, the platform's general-purpose heap, has a fixed id and is never unregistered**, so its storage never goes stale: `Allocator.unregister(.system)` panics. `Allocator.system` is a `static const`, so code takes it with no `copy` ([01](../01-values-and-ownership/moving-values-out.md#constants)).
- **Every other registered allocator is library code implementing `AllocatorImpl`** ([Writing an allocator: `AllocatorImpl`](allocator-implementations.md#writing-an-allocator-allocatorimpl)). Examples are an arena, a heap or a budget wrapper, or one over a platform's memory APIs through `import c`.

**Every registered allocator is of one of three kinds, which say how the memory it hands out goes back:**

- A **heap**, such as `.system` or a TLSF heap, frees each allocation individually.
- An **arena** hands out memory from blocks and frees nothing individually. Freeing into it is a no-op, and a **reset** frees everything it handed out at once ([What a reset does](arena-safety.md#what-a-reset-does)).
- A **wrapper**, such as a budget or a tracking allocator, passes another allocator's allocations through, so they go back as that allocator's do, and keeps accounts of them.

An allocator may draw its memory from one other allocator, its **backing**, such as the allocator a wrapper wraps ([Allocators over other allocators](allocator-implementations.md#allocators-over-other-allocators)).

## The current allocator

**Every thread has a current allocator**, a thread-local that starts as `.system`. It lets code build values without passing an allocator to each call: a block names one, and what is built inside uses it, as at the top of this chapter. It is consulted only in two cases, both where a value is made without an allocator named:

- a constructor of an allocating type records it when it isn't given an allocator, and so does `clone()`;
- a closure's conversion into a `Closure` uses it for an out-of-line context ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).

**A collection grows and frees through the allocator it was built with, for its whole life.** A clone takes the current allocator, so cloning under another one copies a value out of an arena:

```swift
using allocator = .system { kept = spawns.clone() }   // 'spawns' is in an arena; the clone's buffer comes from .system
```

**`using allocator = a` makes `a` the current allocator for its block**, and restores the previous one on exit, including early return.

- **It reads the id in `a` once, on entry.** So reassigning `a` inside the block doesn't change the block's allocator. The read needs no `copy` written, as a `static const` is taken ([01](../01-values-and-ownership/moving-values-out.md#constants)).
- **It holds no borrow of `a`.** So the block may contain an `await`, across which no borrow may be live ([07](../07-concurrency/tasks.md#semantics)).
- **A task suspended inside the block restores its owner's current allocator at the `await`, and makes `a` current again when it resumes** ([07](../07-concurrency/tasks.md#task-functions-explicitly-stepped-coroutines)). Destroying it while it is suspended there changes no thread's current allocator.

### The static allocator

```swift
const primes: List<Int> = makePrimes(below: 1000)    // built by the compiler; its buffer is in read-only data
var more = primes.clone()                            // the clone's buffer comes from the current allocator
more.append(1009)                                    // and grows there, as any list's does
```

**Values in read-only data carry the static allocator, which never allocates or frees at run time.** They need an allocator, since every owning value records the one its storage came from ([How values record their allocator](allocator-implementations.md#how-values-record-their-allocator)). **Read-only data** holds the `const`s, and the global `let`s evaluated at compile time that pass the freezable test ([07](../07-concurrency/global-state.md#initialization-at-startup), [09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).

**Nothing consumes or mutates a value in read-only data, so it is never grown, and it is never destroyed** ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)). So nothing asks the static allocator to allocate or free at run time.

## Allocators and threads

**Every registered allocator must be safe to call from any thread**, since any thread can allocate through a copyable `Allocator` id, including lent work ([07](../07-concurrency/thread-work.md#lending-work-to-other-threads)). So `AllocatorImpl` refines `Synchronized`, the contract under which threads share a value through shared borrows ([07](../07-concurrency/synchronization.md#the-synchronized-contract)). Its methods are non-`mutating`, and change its state only through its own synchronization: atomics, a lock, or state kept per thread inside the implementation.
