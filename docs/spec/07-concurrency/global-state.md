# Global and thread-local state

[07 · Concurrency](../07-concurrency.md)

## Global state

**Safe code has no unsynchronized mutable globals**, since a global is reachable from every thread. A bare global `var` needs `unsafe` to access.

```swift
let config = Published(GameConfig())           // global; safe from any thread
let godMode = Atomic(false)
@threadlocal var scratch = List<Int>()

func damageScale() -> Float { copy config.snapshot().value.damageScale }   // an owner that never waits, then a copy
func debugMenuSet(_ c: owned GameConfig) { config.publish(c) }      // readers see old or new, never torn

func grow() { scratch.append(0) }              // modify access to this thread's 'scratch'
func scan() {
    for x in scratch { grow(); use(x) }        // panics: read by the loop, modified by grow()
}
```

**Every global that safe code reaches has a `Sendable` type, except a `@threadlocal var`** ([What may cross threads: `Sendable`](race-freedom-and-sendable.md#what-may-cross-threads-sendable)). Every thread reaches such a global, while each thread has its own copy of a thread-local. A bare global `var` and an imported C variable may have any unscoped type, since every access to one is `unsafe` and answers for which threads touch it. Safe code can use:

- **`const`s, and `let`s of any `Sendable` type.** Code reaches one only through shared borrows, with no access checks, only the check that its initializer has run where the compiler can't prove it ([below](#initialization-at-startup)). What it holds changes only through its own synchronization: a `Synchronized` value's, such as an `Atomic`, `Mutex`, `Published` or `Once`, or a `Shared`'s count and its value's own ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners));
- **`@threadlocal var`s**: each thread has its own copy ([below](#thread-locals)). `@threadlocal` marks only a `var`.

**A global is declared at a file's top level or as a static member of a type.** A variable declared directly in a function body is a local, and is never `static` or `@threadlocal`.

**A static stored `let`, `var` or `@threadlocal var` is never declared where one declaration stands for many instances.** Each instance would need its own, initialized in no one module's turn ([below](#initialization-at-startup)). Those places are:

- a generic type or an extension of one;
- a protocol extension;
- a type nested in any of these;
- a type or extension local to a function with several instantiations, such as a generic function, a function with a `some P` parameter or a method of a generic type.

**A `static const` is evaluated at compile time for each instance.**

### Thread-locals

**Thread-locals need no synchronization**, since each thread has its own copy. But the static checker can't see a callee touching one, so each access is marked as a read or a change. A conflicting access panics, as `grow()` does above under the loop. The marks never synchronize with another thread. A view of a thread-local is a dynamic access, whose mark is held until the last use of every value that depends on it ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-6-dynamic-accesses)).

**Each thread's copy lives until the thread's teardown** ([below](#thread-teardown)). Copies are initialized on their own thread, before it runs any other Rayo code, in the order globals are and under the same checks ([below](#initialization-at-startup)):

- the startup thread's during startup, interleaved with the globals: the thread that runs `main`, or the one that calls `rayo_init`;
- a thread's started with `Runtime.startThread`: before the body;
- a C thread's when it attaches ([08](../08-c-interop/c-contract-and-embedding.md#embedding-rayo-in-a-c-program)).

### Thread teardown

**A thread's teardown destroys its copies and its objects, on that thread, once it has no other Rayo code to run.** That is when its body returns, at shutdown on the thread that shuts down ([below](#shutdown)), or when a C thread detaches. It runs these steps:

1. The thread's copies are destroyed in reverse order, except those of the prelude's modules and every module they import. Each copy is marked dead before its value is destroyed, so a `deinit` that touches it later in the teardown panics, whether the copy's own destruction runs that `deinit` or a later step does.
2. The thread's objects end ([03](../03-handles-and-objects.md#destroying-an-object)).
3. A `deinit` of step 2 may make or leak another object of the thread, so that step repeats until a round leaves nothing. No object outlives its thread.
4. Those copies, the current allocator among them, are destroyed last, each marked dead first as in step 1.

**A thread that never tears down leaks what its copies and objects own**, as a C thread that exits without detaching does.

### Initialization at startup

```swift
let names = loadNames()      // runs before main, unless it can run at compile time
let table = buildTable()     // may read 'names'; reading a global declared after it is an error
```

**Initialization is eager and ordered.** `const`s are folded at compile time.

**A global `let` goes into read-only data, in every build, exactly when it can be computed and frozen at compile time:** its initializer can run at compile time ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)), and its value passes the **freezable** test ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)). A compile-time run of it that panics is a compile error, as for a `const`. One that exceeds the toolchain's evaluation limits leaves the global to startup, which computes the same value.

**Every other global is initialized at startup**, one module at a time, each module's declarations in source order. **Startup** runs before `main`, or in `rayo_init()` when a C program embeds Rayo ([08](../08-c-interop.md)). The next module is always the first in the build's list ([09](../09-compile-time/attributes-and-runtime-data.md#what-a-build-declares)) whose imports are all initialized. A module outside the prelude's modules and every module they import counts all of those as imports ([11](../11-compilation-model.md#the-prelude)).

**No global is destroyed** ([below](#shutdown)) **or consumed** ([01](../01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)), other than a thread-local's copy, which ends in its thread's teardown.

**Startup keeps code from reading a global before its initializer has run, and keeps other threads out until it ends:**

- **Static check.** Reading a global that isn't initialized yet, directly or through any chain of direct calls from the initializer, is a compile error. A direct call is any whose callee is known statically, including those the language makes for the code ([05](../05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures)). A requirement call inside an imported generic body isn't one: the module's check, made against interfaces alone, can't see it ([11](../11-compilation-model.md#type-checking-is-local)). Imports form no cycle ([11](../11-compilation-model.md#no-import-cycles)), so a chain of calls the check follows ends in the initializer's own module, at its own global or one declared after it.
- **Run-time check, in every build.** For calls the static check doesn't follow, reading a global before its initializer has finished panics. Those are calls through closures, `any P` and function pointers, and requirement calls inside imported generic bodies.
- **Read-only data.** A global in read-only data counts as initialized, for both checks, only once startup reaches its declaration, so whether its compile-time run fits the toolchain's limits never changes what a program does ([11](../11-compilation-model.md#what-the-language-leaves-open)).
- **No other threads during startup.** Initialization is single-threaded. The last initializer's return happens before every later entry into Rayo code on another thread, a queued thread's start included.
    - A thread started with `Runtime.startThread` during startup is queued until then ([Starting a thread: `Runtime.startThread`](thread-work.md#starting-a-thread-runtimestartthread)).
    - A wait that would park until another thread acts panics. `Thread.sleep` and waits with a timeout depend on no other thread, so they don't panic, and a wait whose condition already holds returns at once.
- **Entry.** Entering Rayo code from C panics, in every build, before startup has finished, and from a C thread after shutdown ([below](#shutdown)). The exception is a **nested entry**: one with a Rayo frame below it on its thread, on any of the thread's stacks.
    - During startup only the startup thread has one. An initializer may call C that calls an `@export` or `@c` function back. That entry is let in, while the initialization check still guards every global the callback reads.
    - After shutdown such an entry is let in as before.

### Shutdown

**A program's `main` takes no parameters, and returns `Void`, `Never`, or an `Int32` that becomes the process's exit status.** The runtime shuts down when `main` returns, or when a C program that embeds Rayo calls `rayo_shutdown()` ([08](../08-c-interop/c-contract-and-embedding.md#embedding-rayo-in-a-c-program)).

**At shutdown, the thread that shuts down tears down, and then entry closes:**

1. The thread's teardown runs ([above](#thread-teardown)), so a `deinit` that flushes or closes something runs, and sees that thread's copies, the current allocator included.
2. Entry closes: from then on, an entry from C with no Rayo frame below it on its thread panics ([above](#initialization-at-startup)), and `Runtime.startThread` returns its body unstarted ([Starting a thread: `Runtime.startThread`](thread-work.md#starting-a-thread-runtimestartthread)).

**Other threads don't tear down at shutdown.** When `main` returns, the process exits, ending them where they stand. In a C program that embeds Rayo, a thread that `Runtime.startThread` started still tears down when its body returns. An attached C thread can no longer detach, since detaching enters Rayo as a call from C does, and entry has closed ([08](../08-c-interop/c-contract-and-embedding.md#embedding-rayo-in-a-c-program)).

**No global is destroyed**, not even at shutdown, since a thread still running may read one. Only a thread-local's copies end, each in its own thread's teardown.
