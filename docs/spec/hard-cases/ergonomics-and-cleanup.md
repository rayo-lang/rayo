# Ergonomics and memory cleanup

[Hard cases](../hard-cases.md)

## J. Ergonomics

### J1 · A state machine with timers

**Write a state machine with five states, timers and transitions**, such as an enemy's AI moving between idle, patrol, chase, attack and flee.

- The code must read like ordinary application code: no ownership ceremony beyond `mutable`, and at most one handle lookup per object per state.
- Compare its length to the same code in C#.

---

## K. Freeing memory in practice

**Memory is released at points the code shows, such as a scope's end, an arena reset or the drop of a last owner** ([06](../06-memory-and-allocators.md)). These cases follow memory through a tool that runs once, a server that runs for weeks, a real-time callback, and a program's exit.

### K1 · A program that runs once

**A command-line tool runs once.** It starts threads, runs work on a job system, publishes shared settings through `Published`, drops the last owners of `Shared` values, and resets arenas.

- **Must accept** every construct.
- **Must hold:** memory is freed while the program runs, not only at exit, with no runtime thread and no call the program must place for it.
- State which thread runs each `deinit`, and when.

### K2 · A long-running server

**An event-loop server handles requests on worker threads for weeks.** Each worker has its own scratch arena, which it resets after each request, and connection handshakes are written as `task`s stepped by the event loop. No borrow may be live across a task's `await`, since the task's owner may move or destroy its state between steps ([07](../07-concurrency/tasks.md#semantics)).

The criteria below use these statements, the last four in a handshake task:

```swift
using allocator = frameArena { while running { work(); frameArena.reset() } }   // resets the arena the block allocates from

total += await next()                       // changes one of the task's own locals
results[i] = await fetch(i)                 // assigns an element of one of the task's own locals
let s = await peek(); print(s[0].hp)        // 'peek' returns a view of the resume parameter's data
using allocator = a { … }                   // a block with an await inside
```

- **Must accept** per-request scratch memory, stepped tasks, and a time-based wait driven by the server's own clock.
- Memory must stay bounded as long as each worker returns to its event loop between requests, whether that loop is a C library's that calls Rayo back, or Rayo code that idles in `epoll_wait` or on a futex.
- **Must hold:** what a worker holds while it waits for its next request never makes its arena's next reset panic.
- State what the `unsafe` call to `epoll_wait` promises about the event buffer it hands the kernel, and show a buffer that keeps that promise simply.
- **Must accept** the `frameArena` block above, and a wait inside a loop over a borrowed collection.
- **Must accept** these in the handshake tasks:
    - the compound assignment to `total` and the assignment to `results[i]` above, on a task's own locals;
    - the line with `peek` above, where `peek` returns a view of the resume parameter's data;
    - a `defer` live across an `await` that uses only the task's owned locals;
    - an `await` inside a `using allocator` block, as above.

### K3 · A real-time callback

**A `@noalloc` callback with a real-time deadline, called by a C library on its own thread, reads a `Published` configuration**, as an audio callback reads its mixer settings. Dropping the last owner of a reference-counted value destroys it at once, on the thread that drops it ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)).

- **Must hold:** a callback that reads the configuration never waits, and runs no `deinit` and frees nothing that another thread's `publish` left to it. State how it keeps from dropping the last owner of a replaced configuration.
- **Must accept** a `@noalloc` function that calls a DSP closure it takes as a `@noalloc (mutable MutableSpan<Float>) -> Void`, drops a `Closure<@noalloc () -> Void>` it owns, and calls a `@c noalloc` pointer a C plugin handed over.
- **Must accept** callbacks on the C library's thread that use a `@threadlocal` scratch buffer, which the thread's first entry initializes and its detach destroys. State what the first callback may allocate, and how a `@noalloc` callback avoids it.

### K4 · Cleanup at exit

**A program destroys an arena object whose `deinit` flushes a log file, by resetting its arena**, then returns from `main` a millisecond later.

- **Must hold:** the `deinit` runs before the process exits.
- Define what happens at exit to a thread that is still running, and to memory C still holds a pin into.
- **Must accept** without a panic a `Shared` value whose last owner is a `@threadlocal var` of the thread that runs `main`, and whose `deinit` builds an interpolated `String` before it flushes.
- **Must accept** without a panic a thread-bound object leaked to C, whose `deinit` appends to a `List` it owns, destroyed when its thread's body returns.
