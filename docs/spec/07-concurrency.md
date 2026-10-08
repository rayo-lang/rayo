# 07 · Concurrency

Concurrent code becomes unsafe when two threads reach the same storage without coordination and at least one writes. Rayo lets libraries schedule jobs and create threads, while the language checks what data each piece of work borrows and which values may cross threads. Locks coordinate shared access; tasks can suspend and continue under their owner's control.

```swift
import std.jobs

join({ updateAI(&world.ai, sense: world.perception) },    // may run both closures at once, and returns when both are done
     { integrate(&world.bodies, dt: dt) })                 // fine: each closure writes a different field

join({ steer(&world.ai, around: world.bodies) },
     { integrate(&world.bodies, dt: dt) })                 // error: one closure reads 'world.bodies' while the other writes it

Thread.scope { s in                                        // threads that may borrow this function's locals
    s.spawn { integrate(&world.bodies, dt: dt) }           // runs on another thread
    mix(&world.audio)                                      // runs on this thread meanwhile
}                                                          // the spawned thread has finished here
```

The first `join` can write two separate fields of `world` at once. The second is rejected because one job reads `world.bodies` while the other changes it. `Thread.scope` lets the spawned work borrow a local value because the work finishes before the scope returns.

**Threads, locks and job systems are libraries.** The language gives them checking rules that keep safe code free of data races ([Why safe code can't race](07-concurrency/race-freedom-and-sendable.md#why-safe-code-cant-race)), and the marker protocol `Sendable` for what may cross threads. The runtime starts, parks and wakes threads ([Starting a thread: `Runtime.startThread`](07-concurrency/thread-work.md#starting-a-thread-runtimestartthread), [Parking and waking a thread](07-concurrency/synchronization.md#parking-and-waking-a-thread)). The language's own construct is the `task` function, a coroutine that its owner resumes one step at a time ([`task` functions: explicitly stepped coroutines](07-concurrency/tasks.md#task-functions-explicitly-stepped-coroutines)).

## Subchapters

- [Race freedom and Sendable values](07-concurrency/race-freedom-and-sendable.md)
- [Lending work and starting threads](07-concurrency/thread-work.md)
- [Atomics and synchronization](07-concurrency/synchronization.md)
- [Global and thread-local state](07-concurrency/global-state.md)
- [Explicitly stepped tasks](07-concurrency/tasks.md)
