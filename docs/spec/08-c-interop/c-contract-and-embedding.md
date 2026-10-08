# C's contract and embedding

[08 · C interop](../08-c-interop.md)

At a C boundary, Rayo can check only what the imported or exported types express. C code must uphold the memory and value guarantees that safe Rayo code would otherwise rely on the compiler to enforce. The same boundary defines what the host platform must provide when a Rayo library runs inside a C program.

## What C must uphold

**C that calls Rayo, that Rayo calls, or that reaches Rayo memory has the obligations that `unsafe` Rayo code would have in its place.** Safe Rayo code relies on C keeping them, as it relies on `unsafe` Rayo code keeping its own. They are these:

- **Valid values.** Every value C passes, returns or writes into Rayo memory is valid for its Rayo type ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)):
    - a `Bool` is 0 or 1, and a Rayo enum, or an imported enum declared closed, holds one of its cases;
    - a non-null pointer isn't null, a span's pointer included when its count is 0, since null is a `Span<T>?`'s `nil`;
    - a raw pointer need only be non-null where its type says so, since only `unsafe` code dereferences it;
    - a `String`, `StringView` or `StaticString` holds whole UTF-8 sequences ([04](../04-types/collections.md#strings));
    - a weak pointer, a weak link or a `Handle` holds bits that Rayo gave out for that type, stale or not;
    - a `StaticSpan`, a `StaticString` or a `String` with `cap` 0 points at bytes that stay valid and unwritten for the rest of the run, a `StaticString`'s followed by a NUL.
- **One owner per move-only value.** A move-only value's bytes are never copied to stand for a second value ([10](../10-errors-and-safety/unsafe-code.md#values-views-and-threads)).
- **Values that stay on one thread.** A value whose type isn't `Sendable` reaches Rayo, and is freed through the header, only on its own thread ([10](../10-errors-and-safety/unsafe-code.md#values-views-and-threads)), unless nothing but the raw pointers it holds keeps its type from being `Sendable`. Its own thread is the one Rayo gave it out on, or, for a thread-bound `WeakPointer`, its object's home thread ([03](../03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)).
- **Spans and `mutable` parameters.** Spans, `mutable` parameters and the views C hands Rayo meet these ([10](../10-errors-and-safety/unsafe-code.md#what-unsafe-code-upholds)):
    - a span, or the pointer that a `mutable` parameter passes, reaches its `count` places, or one. For the whole call, each of those places is live, aligned for its type and holding a valid value, and writable for a `MutableSpan` or `mutable` parameter;
    - a `MutableSpan` or `mutable` parameter is the only access to its memory during the call, by C or by Rayo, and nothing writes the memory a `Span` or `StringView` parameter views;
    - a view, or a value holding one, that C returns to Rayo or writes into Rayo memory, through a `mutable` parameter, a `MutableSpan` or a pointer, addresses live memory for as long as its dependency set says. Rayo gives it that set by rules 3 and 4 ([02](../02-views-and-dependencies.md#dependencies)).
- **Known stacks.** Rayo code runs only on a stack whose bounds the runtime knows, so running out of it panics instead of writing past its end ([10](../10-errors-and-safety/panics.md#panics)):
    - C that switches a thread between stacks, as a fiber scheduler does, declares the new stack's bounds with `rayo_thread_set_stack` after each switch, back to the thread's own stack included, before Rayo code runs there ([below](#embedding-rayo-in-a-c-program));
    - a Rayo frame that such a switch suspends resumes only on the thread it began on, whose accesses, allocator uses and thread-locals it uses;
    - a fiber abandoned with Rayo frames on it never returns from them. C keeps its stack allocated and unmoved for the rest of the run. What the frames own leaks, and what they borrow stays borrowed, so a reset of an allocator they use panics ([06](../06-memory-and-allocators/arena-safety.md#what-a-reset-does)).
- **Stack for C.** C that Rayo calls uses no more stack than the call checks is left ([The stack a C call needs](imports-and-inline-c.md#the-stack-a-c-call-needs)), or runs on a stack of its own.
- **Frames end by returning.** Control leaves a Rayo frame for good only when the frame returns, apart from the stack switches above, and its memory stays allocated until then. C never `longjmp`s over one, unwinds through one, ends its thread beneath one, or frees or reuses a stack that holds one.
- **Unloading.** C never unloads the program's code, or frees memory that its runtime or globals use, unless `rayo_shutdown` has returned `true` ([below](#embedding-rayo-in-a-c-program)), which it does only once nothing can run Rayo code or the runtime's code again.
- **Entering by a call.** C enters Rayo only by an ordinary call, never from a signal handler or an interrupt, which could arrive while its thread is in the middle of Rayo code.
- **Values C hands to Rayo.** A value C hands to Rayo in one of these ways is Rayo's from then on, so C never uses or frees it again:
    - passing it to an `owned` parameter, directly or through a `@c` pointer;
    - returning it from a C function Rayo called;
    - writing it into Rayo memory, such as through a `mutable` parameter Rayo lent C.
- **Borrowed values.** A value passed to a borrowed parameter stays its sender's, so C never frees or keeps one that Rayo passed it borrowed, nor passes it to an `owned` parameter.
- **Owning values Rayo hands C.** C frees a `List`, `String` or `TrailingArray` that Rayo handed it ([Ownership that crosses to C](calling-rayo-from-c.md#ownership-that-crosses-to-c)) at most once, and only through the free function the header declares for its type. It never frees one after passing it to an `owned` parameter, returning it to Rayo or writing it into Rayo memory. It reads its elements only until the allocator its `alloc` word names is reset or unregistered ([06](../06-memory-and-allocators/arena-safety.md#what-a-reset-does)).
- **Rayo-owned memory.** C reads Rayo-owned memory only while Rayo keeps it alive and isn't writing it, and writes it only where Rayo code with exclusive access could. It writes a `TrailingArray`'s header, or a struct whose flexible array member's elements share its tail padding, field by field, never as a whole struct, and never passes one to Rayo as a `mutable` parameter or in a `MutableSpan`. A whole store, or a write to a struct lent either way, may write all its bytes, the elements in its tail padding included ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)).
- **Immutable and synchronized memory.** C never writes memory Rayo treats as immutable, such as read-only data or a `Frozen` value behind a `Shared`, which Rayo reads without a mark. It writes a `Synchronized` value only through that value's own synchronization.

**Breaking one is undefined behavior**, as a wrong `unsafe` block is. So an entry point that takes a Rayo type relies on C to pass a valid value, while one that takes the raw form accepts anything C passes:

```swift
enum NavMode: Int32 { case walk, fly }

@export(c) func nav_set_mode(_ mesh: WeakShared<NavMesh>, _ mode: NavMode) { ... }   // C must pass a valid case

@export(c) func nav_set_mode_checked(_ bits: UInt64, _ raw: Int32) -> Bool {  // accepts anything C passes
    guard let mesh = WeakShared<NavMesh>(bits: bits) else { return false }   // nil unless the bits name a live NavMesh
    guard let mode = NavMode(rawValue: raw) else { return false }            // nil unless 'raw' is a case's value
    ...
}
```

**An entry point that takes the raw form, as `nav_set_mode_checked` does, converts it with Rayo's checked conversions:**

- a `UInt64` with `WeakShared<T>(bits:)`, with `WeakPointer<T>(bits:)`, which also checks the thread, since an object is used only on its home thread ([03](../03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c)), or with `Handle<T>(bits:)`;
- a raw integer with `E(rawValue:)`.

## The platform, and embedding Rayo in C

### What the runtime needs from the platform

**The runtime needs these from the platform:**

- memory for `.system`, the platform's general-purpose heap ([06](../06-memory-and-allocators/allocator-basics.md#allocator-values));
- threads, which `Runtime.startThread` starts ([07](../07-concurrency/thread-work.md#starting-a-thread-runtimestartthread));
- the bounds of each stack Rayo code runs on, so running out of one panics instead of writing past its end: a C thread's when it attaches, and a fiber's when C declares it ([above](#what-c-must-uphold));
- a way to park a thread on an address and wake it, which blocking primitives wait with ([07](../07-concurrency/synchronization.md#parking-and-waking-a-thread));
- a monotonic clock for timeouts, such as a parked thread's;
- a way to report a panic ([10](../10-errors-and-safety/panics.md#panics)).

### Embedding Rayo in a C program

**A C program can embed Rayo, and then runs startup and shutdown itself**, with `rayo_init` and `rayo_shutdown`, where a Rayo program runs them around `main` ([07](../07-concurrency/global-state.md#initialization-at-startup)). It calls Rayo through exported functions and these C exports of the runtime:

| Function | Purpose |
| --- | --- |
| `void rayo_init(void)` | Runs startup, once: the calling thread's thread-locals and the other globals' initializers, in startup order ([07](../07-concurrency/global-state.md#initialization-at-startup)) |
| `bool rayo_shutdown(void)` | Shuts the runtime down: destroys the calling thread's thread-locals and objects (below), and closes entry ([07](../07-concurrency/global-state.md#shutdown)), and returns whether the runtime has stopped (below) |
| `void rayo_thread_attach(void)`, `void rayo_thread_detach(void)` | Attach and detach threads Rayo didn't create, such as a middleware library's callback thread. Attaching an attached thread, or detaching one that isn't, does nothing |
| `void rayo_thread_set_stack(void* low, void* high)` | Declares the bounds of the stack the calling thread has just switched to, such as a fiber's, before it runs Rayo code there |

- **`rayo_init`.** Startup is single-threaded ([07](../07-concurrency/global-state.md#initialization-at-startup)). So an entry from another thread before `rayo_init` has finished panics, and the threads the initializers started with `Runtime.startThread` are queued, and start when it returns. A second call panics too. C that an initializer calls may call back into Rayo on the same thread, and the runtime checks guard each global it reads.
- **`rayo_shutdown`.** Only the calling thread's thread-locals and objects are destroyed, since a thread's teardown runs only on that thread ([07](../07-concurrency/global-state.md#thread-teardown)). Any other thread still attached, the one that called `rayo_init` included, keeps its copies, which leak. An entry from a C thread afterwards panics, except a nested one, which is let in as before ([07](../07-concurrency/global-state.md#initialization-at-startup)). It returns `true` only when nothing can run Rayo code or the runtime's code again: every thread `Runtime.startThread` started has ended, and no thread has a Rayo frame on any of its stacks. Only then may C unload the program's code ([above](#what-c-must-uphold)).
- **Attaching threads.** Attaching is also implicit on first entry ([C entries and threads](calling-rayo-from-c.md#c-entries-and-threads)), and initializes the thread's thread-locals. Detaching destroys them and the thread's objects, on that thread ([07](../07-concurrency/global-state.md#thread-teardown)). A thread that exits without detaching, or is still attached when another calls `rayo_shutdown`, leaks them instead. Both enter Rayo as a call from C does, with the same checks ([C entries and threads](calling-rayo-from-c.md#c-entries-and-threads)), so after `rayo_shutdown` either one fails as such an entry does (above).
- **Not from inside Rayo.** `rayo_thread_detach` and `rayo_shutdown` panic, before they do anything, on a thread with a Rayo frame on any of its stacks, a suspended fiber's included. That holds whether the thread is inside a call into Rayo or in a C call that Rayo made, since its Rayo frames may still use what they destroy.
- **Detaching on return.** `Runtime.detachOnReturn()`, called on a thread Rayo didn't create, detaches it when the thread next returns to C with no Rayo frame on any of its stacks, as `rayo_thread_detach` would there. On a thread Rayo started, which tears down when its body returns, it does nothing. So a `@c func` that is the start routine of a thread made through the C API tears its thread down with no C of its own.
