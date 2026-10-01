# 14 · Decisions and open questions

| Decision | The question it settles |
| --- | --- |
| [D0](#d0-never-forbid-a-reasonable-pattern-choose-how-to-check-it) | What happens to a pattern the compiler can't prove safe? |
| [D1](#d1-no-lifetime-annotations-static-borrows-within-a-function-dynamic-references-across) | How are references checked without lifetime annotations? |
| [D2](#d2-no-implicit-reference-counting-sharedt-only-for-immutable-data) | Does the language count references? |
| [D3](#d3-move-only-collections-not-copy-on-write) | Are collections ever copied implicitly? |
| [D4](#d4-every-feature-can-be-implemented-in-portable-c) | Can Rayo run where the only toolchain is a C compiler? |
| [D5](#d5-an-allocator-is-a-value-and-each-owning-value-records-its-own) | How does a container know where its storage came from? |
| [D6](#d6-no-class-inheritance-no-exceptions-no-ast-macros-no-duck-typed-generics) | Which familiar features does Rayo leave out? |
| [D7](#d7-a-floating-point-literal-takes-its-type-from-context-and-is-a-double-without-one) | What type is `0.5`? |
| [D8](#d8-memory-safety-checks-stay-in-shipping-builds-diagnostic-checks-follow-the-profile) | Which runtime checks stay on in shipping builds? |
| [D9](#d9-stepped-coroutines-in-the-language-threads-and-structured-concurrency-in-std-checked-by-the-languages-rules-no-executors-or-actors) | What does the language provide for concurrency? |
| [D10](#d10-global-state-must-choose-its-concurrency-behavior-no-unsynchronized-mutable-globals) | How are globals kept free of races? |
| [D11](#d11-deferred-reclamation-by-per-thread-grace-periods-not-a-global-stop) | When is memory that a view may still be reading reused? |
| [D12](#d12-the-spec-defines-the-language-its-runtime-guarantees-and-library-contracts-not-libraries-or-tools) | What does the spec define, and what does it leave to libraries and tools? |
| [D13](#d13-c-interop-is-unsafe-the-spec-defines-the-mapping-not-the-boundary) | What does the spec promise where Rayo meets C? |
| [D14](#d14-copies-are-written-out-taking-a-value-moves-it-a-binding-of-a-place-borrows-it-copy-duplicates) | When is a value copied? |
| [D15](#d15-parameter-conventions-are-adjectives-function-modifiers-are-verbs) | What are parameter conventions and function modifiers called? |
| [D16](#d16-one-sendable-contract-for-crossing-threads-and-objects-that-are-thread-bound-unless-declared-concurrent) | What may cross threads, and how is an object shared between them? |
| [D17](#d17-literals-take-their-type-by-protocol-and-allocate-only-where-the-type-is-written-an-array-is-inline-a-list-grows) | What can a literal become, and what are the array types called? |
| [D18](#d18-a-structs-stored-fields-are-its-primary-initializer-every-other-init-delegates) | Where are a struct's fields declared, and how is a value built? |
| [D19](#d19-when-and-if-are-expressions-and-there-is-no-ternary) | How does code choose a value by cases? |

## D0. Never forbid a reasonable pattern; choose how to check it

**Every reasonable systems pattern is expressible, and the language puts each one in the cheapest tier that can check it.**

**Problem.** Systems code is full of patterns no static checker proves: back-pointers, observers, service pointers, intrusive lists, globals. A language that forbids them pushes programmers into `unsafe`, losing the checking, or into contortions, losing productivity.

```swift
func heal(_ e: mutable Enemy) { e.hp = 100 }         // static tier: a borrow, checked at compile time, free

struct Sprite(var renderer: WeakPointer<Renderer>)   // dynamic tier: a stored link, checked each time it is used

unsafe {                                             // unsafe tier: raw memory, not checked at all
    let p: *Particle = ptr(to: &particles[0])
    p[3].pos = .zero
}
```

**Decision.** There are three tiers ([01](01-values-and-ownership.md#tiers-of-checking)): **static**, checked by the compiler for free; **dynamic**, a visible runtime check; and **`unsafe`**, which nothing checks, for code that is inherently unsafe. A pattern can land in the dynamic tier because the static checker can't prove it, but it is never forbidden for that reason, and never forced into `unsafe`.

**Why.** Dynamic checks are cheap, and they are visible in the type, which keeps Rayo's first design pillar, visible costs ([Why Rayo](why-rayo.md#design-pillars)).

**Rejected.**

- The Rust stance: a link the static checker can't prove is an index that nothing checks for staleness, or a counted owner with an interior-mutability wrapper, as `Rc<RefCell<T>>` is, where Rayo's weak pointers and handles check a link without counting (D1, D2).
- Hylo's model, where references are never stored, which forbids back-pointers and observers instead of checking them.

## D1. No lifetime annotations: static borrows within a function, dynamic references across

**Borrows are checked statically inside each function, with no lifetime annotations, and references stored across functions are checked dynamically, each time they are used. Opt-in `where` clauses and `keep` state what the defaults can't.**

**Problem.** A reference is safe only while its target is alive and nothing else changes it. Inside one function the compiler can see that. A reference stored in a long-lived object, such as a sprite's pointer to its renderer, outlives the function that stored it, and checking it statically takes lifetime parameters, as in Rust's `struct Sprite<'a> { renderer: &'a Renderer }`.

```swift
// A borrow, with no annotations: after a call, the list passed as 'out' borrows what 'text' views.
func splitLines(_ text: StringView, into out: mutable List<StringView>) { ... }

// A stored reference: checked each time it is used, and nil once the parent is destroyed.
struct Node(var parent: WeakPointer<Node>?, var children: List<UniquePointer<Node>>)
```

**Decision.**

- **Borrows** (parameters, bindings, scoped values) are checked one function at a time, through dependency sets the compiler works out ([02](02-views-and-dependencies.md#dependencies)). A view of memory that can be freed is `Scoped` and never outlives the scope that lent it, unless it reads that memory only through scoped views it hands out, as a `Slice` does ([02](02-views-and-dependencies.md#scoped-values)). A scoped result depends on every argument the call lends it and on what its scoped `owned` arguments carry ([02](02-views-and-dependencies.md#dependencies)'s rule 3) unless a `where return borrows …` or `where return outlives …` clause names fewer, and `keep` marks a closure parameter whose views may be kept.
- **Stored references** are generational and checked at each use: a `Handle<T>` into a pool, a weak pointer to an object ([03](03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)), or a `Slice<T>` of a buffer ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)). Conflicting uses of a thread-bound object panic; on a concurrent object, a conflicting use from the same thread panics and one from another thread waits.

**Why.** Lifetimes buy one thing this design doesn't: **stored references between long-lived objects that are checked at compile time, at no run-time cost**. They charge for it everywhere: annotations that cascade through callers, lifetime parameters on every type that holds a reference (`World<'a>`), and signature changes that ripple out whenever what a type borrows changes. Rust code with long-lived cross-links usually ends up on `Rc<RefCell<>>` or indices anyway, which are dynamic checks too.

**Cost.** Each dynamic-tier use is checked: a stale reference reads `nil`, and a conflicting access panics or waits ([01](01-values-and-ownership.md#tiers-of-checking)).

| Pattern | With lifetimes | In Rayo | Residual cost |
| --- | --- | --- | --- |
| Long-lived struct pointing at a longer-lived object, or an arena graph | `&'a T`, free | `WeakPointer<T>`, or indices | 8 B per link; a check per access |
| The same, with the object shared across threads | `&'a T` where `T: Sync`, free | `ConcurrentWeakPointer<T>` | 8 B per link; a check per access, which takes the object's lock unless it is lock-free |
| Long-lived view into a long-lived buffer, such as stored parse results | `&'a [T]`, `Msg<'buf>`, free | `Slice<T>`, or keep the parse in one function | The buffer lives in a concurrent object, as a `Blob` of `Pod` elements or a `List`; a check per `read()` or `lock()`, plus the lock for a lockable buffer; never a per-element cost |
| Callback that hands out views the caller keeps (`forEachLine`) | `FnMut(&'a str)` | `keep` on the closure type's parameter ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)) | One keyword. The default, call-scoped, is Rust's elided `for<'a>` |
| Accessor whose projection outlives the access | `fn get(&self) -> &T`, elided | `where yield borrows self`, verified ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)) | One clause per such user accessor. Accessors without one are access-bound, which lets one yield a temporary |
| Struct holding borrows of several places, with a result from one of them | `Query<'a, 'b>`, `-> &'b Entry` | A dependency set per stored field, and `where return outlives q.table` ([02](02-views-and-dependencies.md#naming-a-field)) | One clause item. The split doesn't survive storage in a collection, an enum payload, a `Box` or a generic `T` |
| Proof that aliased mutation can't happen through stored references | Compile error | Runtime panic, for uses on one thread; a concurrent object's lock makes other threads wait instead | A bug found in testing instead of at compile time |

The last row is the real loss.

**Rejected.** Rust-style lifetime parameters, for the costs above.

## D2. No implicit reference counting; `Shared<T>` only for immutable data

**Nothing in the language counts references implicitly, and its one general counted type, `Shared<T>`, holds only immutable data.**

**Problem.** Several parts of a program often need the same data: the nodes of a graph, or a loaded asset many systems use. Reference counting (RC) is the usual answer, and cycles, values that count each other and are never freed, are its hardest failure mode.

**Decision.** Values move ([01](01-values-and-ownership.md)). Graphs use handles or weak pointers (D1), which never keep their target alive. `Shared<T>` is atomic RC with an explicit `share()`, over a `T` that is `Frozen`: deeply immutable, which the compiler derives ([06](06-memory-and-allocators.md#frozen-types-with-no-interior-mutability)).

**Why.** RC over immutable data can't form a cycle: a `Shared` points only at values that existed before it, and nothing it reaches can be changed to point back. That removes RC's hardest failure mode.

**Cost.** std's `Sender`, `Receiver` and `Future` count their few owners internally, so some of their cycles, such as a `Receiver` queued in its own channel, leak ([07](07-concurrency.md#queues-and-channels)).

**Rejected.**

- ARC (Swift): hidden retain and release traffic, and cycles.
- Rc/Arc with interior mutability (Rust `Rc<RefCell<T>>`), whose counted mutable values can form cycles.

## D3. Move-only collections, not copy-on-write

**`List`, `String` and `Map` are move-only: copying one requires `.clone()`.**

**Problem.** Copying a collection is O(n). Swift hides the copy behind copy-on-write (COW), which defers it to the first mutation. Wherever it lands, a hidden O(n) copy is a latency spike.

```swift
var a = List<Int>([1, 2, 3])
let same = a              // a borrow: another name for 'a', and nothing is copied
var c = a.clone()         // explicit deep copy: allocates, visibly
var d = copy a            // error: 'List<Int>' is not copyable
owned var b = a           // move: 'b' takes over the buffer, and 'a' can't be used after this
```

**Decision.** Every type that owns memory is move-only ([01](01-values-and-ownership.md#values)), so it is copied only by a `clone()` the code writes.

**Why.** An explicit copy costs one word at the call site, and D14's rules keep the common cases free of copies. The one deferred copy is a `String` made from a literal, which uses the literal's immortal bytes until it is first written or grown ([04](04-types.md#literals)): a copy of at most the literal's bytes, once per string, with no count to keep, since nothing ever writes or frees those bytes.

**Rejected.** Swift's COW, which needs a refcount per buffer and can copy a whole collection, of any size, at whichever mutation first finds its buffer shared.

## D4. Every feature can be implemented in portable C

**The language has no feature that portable C can't implement, so a platform whose only toolchain is its vendor's C compiler can run Rayo when that compiler and its ABI meet [12](12-compilation-model.md#what-a-target-must-provide)'s target requirements.**

**Problem.** On some platforms, consoles among them, the toolchain belongs to the platform holder, who maintains and certifies it under NDA, and it includes a C compiler. A feature that needs a particular code generator would tie every Rayo toolchain to a code generator kept matched to each of those toolchains for the platform's whole life.

**Decision.** Everything the language defines can be implemented in portable C ([12](12-compilation-model.md#what-a-target-must-provide)). How a toolchain generates code is its own design (D12), and two implementations may disagree about a safe program only in what the language leaves open ([12](12-compilation-model.md#what-the-language-leaves-open)).

**Why.** A toolchain can reach any such platform through the C compiler its platform holder certified, and keep that platform's debuggers, profilers and crash tools. Nim compiles to C, and IL2CPP and GameMaker's YYC compile to C++, in shipping products.

**Cost.** No unwinding, no guaranteed tail calls (only some compilers have `musttail`), and no computed goto, which C has only as an extension. A target's C ABI and compiler must meet [12](12-compilation-model.md#what-a-target-must-provide)'s requirements, among them 64-bit pointers and a reported bound on each function's stack use, which the stack check needs.

**Rejected.** Features that need their own code generator. Tracking each vendor's LLVM fork, sysroot and ABI quirks under NDA is the biggest cost of bringing Swift or Rust to those platforms.

## D5. An allocator is a value, and each owning value records its own

**An `Allocator` is a copyable id of a registered allocator, not a type parameter, and each owning value records where its storage came from.**

**Problem.** An owning container has to know which allocator to free into. When its storage comes from an arena, it also has to tell whether the arena was reset since, so a stale container panics instead of reading reused memory.

```swift
let levelHeap = Allocator.register(TlsfHeap(size: 64.mb))
var a = List<Enemy>()                              // current allocator
var b = List<Enemy>(allocator: levelHeap)          // explicit, and still the same type: List<Enemy>
```

**Decision.** Registered allocators are named by `Allocator` ids, and each thread has a current allocator that constructors use by default. Each owning value stores an **allocator word**, which names the allocator its storage came from and dates the storage against that allocator's resets ([06](06-memory-and-allocators.md#how-values-record-their-allocator)).

**Why.** Collection types don't split by allocator, and the check that makes arena resets memory-safe needs nothing but the value itself: no list of what an arena handed out.

**Cost.** One 8-byte word per owning value, or per allocation or page for a container that keeps several ([06](06-memory-and-allocators.md#a-containers-words-must-cover-all-of-its-storage)), which C sees as a `List`'s or `String`'s `alloc` field ([09](09-c-interop.md#c-representations)).

**Rejected.**

- Allocator as a type parameter (`Vec<T, A>`, `std::pmr` variants), which splits collection types.
- An implicit context parameter (Jai, Odin), which complicates the C ABI and callbacks.
- A pointer plus vtable per container: 16 bytes, and still nothing to check a reset against.

## D6. No class inheritance, no exceptions, no AST macros, no duck-typed generics

**Rayo leaves out class inheritance, exceptions, AST macros and duck-typed generics, and covers what each is used for with other features.**

**Problem.** Each is common in the languages Rayo draws on, and each costs something: layout coupling, unwinding, a second language inside the first, or type checking deferred to every use.

**Decision.** Each is replaced:

- **Inheritance:** composition, protocols and enums cover polymorphism without vtable-layout coupling or fragile base classes, and `any P` covers open-set dynamic dispatch, explicitly ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).
- **Exceptions:** typed `throws` returns the error as a value, at the cost of a return ([11](11-errors-and-safety.md)). Rayo never unwinds, and C that unwinds or `longjmp`s through a Rayo frame is undefined behavior ([09](09-c-interop.md#what-c-must-uphold)).
- **Macros:** compile-time evaluation, static reflection, `static if` and `static for` over code and declarations, and attributes ([10](10-compile-time.md#generating-declarations)). The compiler runs ordinary code to build checked declarations. Syntax macros, over tokens or syntax trees, would add a second language, hurt tooling inside expansions, and slow compiles.
- **Duck-typed generics:** Zig checks a generic only when it is instantiated. Rayo checks one once, at its definition, which keeps type checking fast, lets errors name the missing constraint, and lets tools see a generic's members without instantiating it. What generic code still checks per instantiation, such as compile-time code, and where an instantiation can still fail, is listed in [05](05-protocols-generics-and-closures.md#protocols-and-generics).

## D7. A floating-point literal takes its type from context, and is a `Double` without one

**A floating-point literal is typed by its context: the expected type, the other operand of an operator, or a generic parameter the call's other arguments bind ([05](05-protocols-generics-and-closures.md#operators)). With none, it is a `Double`. Widening along [04](04-types.md#conversions)'s fixed order is implicit.**

**Problem.** A language has to pick a type for `0.5` where nothing else decides it. Graphics and simulation data is mostly 32-bit, which argues for `Float`, but a `Float` default rounds a value silently, and implicit widening then hides the rounding:

```swift
let rate = 0.1                   // as a Float, 0.100000001490116…
let tax: Double = price * rate   // 'rate' widens to Double, carrying the Float's error into Double math
```

**Decision.**

```swift
pos += dir * 0.5                 // Float: the other operand, a Vec3, types the literal
let step: Float = 0.5            // Float: the annotation does
let speed = 0.5                  // Double: nothing does
pos += dir * speed               // error: 'speed' is a Double, which never narrows implicitly
```

**Why.**

- Where a literal meets `Float` data, as an operand, an argument, a field's initializer or an annotated binding, the context already makes it a `Float`. The default decides only literals with no context, mostly locals and constants, and there precision is the safer choice.
- Every narrowing is loud. A `Double` meeting `Float` data widens the `Float` exactly, and where the result must be a `Float`, as a `Float` field or a `Vec3` operand must, it is a compile error, since narrowing is explicit, while a `Float` default rounds silently, as above.
- On current CPUs a scalar `Double` add or multiply costs what a `Float` one does. What `Float` saves is memory, bandwidth and SIMD width, and those come from types, such as `Vec3`, `List<Float>` or a struct's fields, which also give literals their context.
- Large coordinates, simulation time and accumulators need `Double`.

**Rejected.**

- `Float` as the default, since it rounds silently, as above.
- No default, making a literal with no context an error, since every `let x = 0.5` would then need a type, even where precision is all that matters.

## D8. Memory-safety checks stay in shipping builds; diagnostic checks follow the profile

**Bounds checks stay on in shipping builds, and integer overflow wraps there.**

**Problem.** Every runtime check costs something, so a language has to choose which ones a shipping build keeps.

```swift
@checks(.all) func accumulate(_ total: mutable Int, _ xs: Span<Int>) { … }   // overflow checked here, even in ship

unchecked {                        // the checks this block's own code makes are off, bounds included
    for i in 0..<n { dst[i] = src[i] * k }
}
```

**Decision.** Memory-safety checks, bounds included, are on in every profile, and only an `unchecked` block removes them, per scope. Diagnostic checks, such as integer overflow, catch bugs whose failure is still memory-safe. They follow the build profile, so overflow wraps in `ship`, unless the build's settings for a module or a scope's `@checks(…)` override it, and an `unchecked` block turns them off ([11](11-errors-and-safety.md#check-levels)).

**Why.**

- Bounds checks are cheap, since they almost never fail, and they turn memory corruption into a panic.
- Overflow checks cost more, since they get in the way of vectorization, and catch fewer bugs in practice.
- `unchecked` makes a failed memory-safety check undefined behavior, as `unsafe` code can, but is a keyword of its own, so a search for either finds one kind of risk.

## D9. Stepped coroutines in the language; threads and structured concurrency in std, checked by the language's rules; no executors or actors

**The language's own concurrency construct is the explicitly stepped `task` coroutine, and threads and structured concurrency are std library code, made safe by rules the language applies to every call and by the promise std's `unsafe` lending code makes ([07](07-concurrency.md#the-librarys-promise)).**

**Problem.** Programs need two kinds of concurrency: work forked across threads and joined, such as a frame's job graph, and sequences that wait across steps, such as a door that opens, waits half a second, and closes.

```swift
import std.jobs

join({ updateAI(&world.ai, sense: world.perception) },     // writes ai, reads perception
     { integrate(&world.bodies, dt: dt) })                  // writes bodies: no overlap, so both may run at once
```

If the first closure also read `world.bodies`, the call would be rejected, as `f(&x, x)` is.

**Decision.**

- **In the language: stepped `task` coroutines.** A `task func` suspends at `await`, and its owner resumes it one step at a time: a game once per frame, a server once per event-loop turn ([07](07-concurrency.md#semantics)).
- **In std: threads and structured concurrency.** `join`, parallel loops, scoped threads, long-lived threads, queues and locks are built on the runtime's primitives for starting, parking and waking threads and on sections (D11).
- **The checks are the ones every call gets.** Only `Sendable` values reach another thread (D16); closure kinds say whether a function value may be called by many threads at once, by one at a time, or once; exclusivity holds across a call's arguments; and a scope absorbs what the closures it is given borrow ([07](07-concurrency.md#lending-work-to-other-threads)).

**Why.**

- Executor-driven async/await and actors fit request-driven I/O, not code whose owner steps it on its own schedule, such as a job graph each frame, and neither an executor nor an actor is needed: the owner of a task set decides when to step it.
- Exclusivity doubles as race detection for any code that lends work to other threads, because a borrow never outlives the function body that made it (D1).
- Asynchronous I/O is library work: it completes into a `Future` or another value the program polls, or wakes a waiting task through the task's `Waker` ([07](07-concurrency.md#awaitables)). Rayo keeps the waker half of Rust's async and drops the executor, since the program decides when and where tasks step.

**Rejected.**

- General-purpose async/await with executors, and actors. An actor is a pattern: a `Thread.loop` over a mailbox queue, owning its state. As a feature it would bring a scheduler, hidden suspension points and reentrancy, and serialize data-parallel work that fork-join handles statically.
- Fork-join syntax, such as `parallel for`. The language would have to define a scheduler interface and track locks and context per job, and none of that is safer than std's checked calls.

## D10. Global state must choose its concurrency behavior: no unsynchronized mutable globals

**Every global declares how it behaves under concurrency, and safe code has no unsynchronized mutable globals.**

**Problem.** Any thread can reach a global, and nothing at a call shows that the callee touches one, so the static checker can't see two threads, or a caller and its callee, using one global at once.

```swift
let config = Published(GameConfig())           // readers see the current value; writers publish a new one
let godMode = Atomic(false)
@threadlocal var scratch = List<Int>()
var hits = 0                                   // a bare global var: every access needs unsafe
```

**Decision.** Safe code uses `const`s, `let`s of any `Sendable` type (D16), which every thread reads through shared borrows and whose contents change only through their own synchronization, and `@threadlocal var`s, where conflicting accesses on the thread panic ([07](07-concurrency.md#global-state)). A bare global `var` may be declared, but every access to it needs `unsafe`.

**Why.** A global has no visible parameter at its use sites, so its concurrency behavior belongs in its declaration, where a `let`'s type says whether and how it changes: not at all, or through a lock, an atomic or a published snapshot. Passing state explicitly (`mutable World`) stays free and statically race-checked.

**Rejected.**

- Banning global state, which violates D0: configuration, logging, registries and service locators are reasonable patterns.
- Bare global `var`s checked at each access: sound, since a conflict panics, but contention on a global is normal and should wait, not crash. Panic-on-conflict suits aliasing bugs on one thread, where contention is abnormal.
- Unchecked globals, which are unsound: a callee could reallocate a global its caller has borrowed, or two threads could race on it.
- Effect annotations tracking global access, which color functions: every caller of an annotated function carries the annotation too.

## D11. Deferred reclamation by per-thread grace periods, not a global stop

**Memory that a thread may still be viewing is reused only after every thread has, on its own schedule, passed a point where it held no view.**

**Problem.** Resetting an arena, unregistering an allocator, destroying a concurrent object, whose lock, and a lock-free one's value, other threads may still reach, and publishing a new `Published` value all make memory unreachable while a view, on any thread, may still read it. Tracking views one by one would put a cost on every view.

**Decision.** A value destroyed, or memory made unreachable, while something may still use it is **retired**: its `deinit` and its release wait until nothing can. Where a view may still read it, that wait is a **grace period**, as in read-copy-update (RCU) ([08](08-grace-periods-and-checkpoints.md#grace-periods-how-deferred-memory-is-reclaimed)):

- **Sections.** A thread is inside a **section** while it runs Rayo code that might hold a view. Retired memory that a view may still read is not reused before every thread has been outside a section since it was retired.
- **Checkpoints.** A long-lived thread body leaves its section at a `checkpoint`, which stands only at the top level of an entry body: `main`, an `@entry` function, a C entry or an entry literal. A parking wait or an entry call placed there counts as one when it qualifies.
- **Nothing is held across one.** No borrow or dynamic access is live across a checkpoint, as none is across an `await`, except the places a qualifying wait or entry call borrows, which must lie in a global or in the entry body's own storage ([08](08-grace-periods-and-checkpoints.md#what-a-wait-may-borrow)).
- **Who reclaims.** Outside exit, no thread waits for another to reclaim memory: a runtime thread reclaims it where the runtime starts one, and so do the `Runtime.reclaim` calls the program places, never inside an unrelated thread's code. At exit, the exiting thread reclaims what is left.

**Cost.**

- A thread that stays in one section for a long time delays reclamation. Memory grows, but before exit nothing stalls.
- A long-running thread body must reach a checkpoint, or a wait or entry call that qualifies as one, regularly.

**Rejected.**

- A global quiescent point the program declares once per iteration of its main loop, waiting for every thread to be idle or parked in a `@quiescent` call. One slow thread would stall everyone, `@quiescent` would spread up the call graph, and it would build a main loop into the runtime.
- Tracking each view, by reference counting or hazard pointers: exactly the hidden per-view cost Rayo refuses.

## D12. The spec defines the language, its runtime guarantees and library contracts, not libraries or tools

**The spec defines the language, the runtime behavior programs can rely on and the contracts libraries implement. How a toolchain or runtime implements them, and everything built on the language, is out of scope.**

**Problem.** Much of what a program needs from Rayo is libraries and tools: containers, allocators, queues, serializers, a job system, a hot reloader. And every guarantee can be implemented in more than one way. The spec has to draw a line between what it defines and what is built on it or left to an implementation.

**Decision.** The spec defines:

- the language itself;
- the runtime behavior programs can rely on: sections, grace periods and checkpoints, the earliest point retired memory may be reused, where `deinit`s run, what panics, and the order of startup, thread teardown and exit;
- the contracts libraries implement, such as the protocols the language calls or derives (`Sequence`, the literal protocols, `Equatable`, `Awaitable`, `Attribute`), every `unsafe protocol`, such as `Synchronized` and `AllocatorImpl`, the `@parks` promise, and the promise of code that lends a scoped value to another thread ([07](07-concurrency.md#the-librarys-promise), [11](11-errors-and-safety.md#safe-modules)).

The spec describes a std type where its rules or examples use it, such as `List` and `String` for literals, and the locks, queues and `Published` for concurrency, and then states what that type checks ([11](11-errors-and-safety.md#the-checks)). The rest of std's catalog, and runtime policy such as when reclamation runs, are out of scope.

**Rejected.** Specifying std's whole catalog, such as its allocator implementations and serializers, or how the runtime implements its guarantees. Each such choice would become a spec rule, and language rules would grow exceptions to serve one library or one implementation.

## D13. C interop is unsafe; the spec defines the mapping, not the boundary

**Crossing between Rayo and C is unsafe in both directions, and the spec defines how each side appears to the other, not a guarded boundary between them.**

**Problem.** Platform SDKs and middleware speak C, and C calls Rayo back, from callbacks or from a C program that embeds Rayo. Rayo can't check what C does, so what does the spec promise where the two meet?

```swift
public struct GpuBuffer private init(let id: UInt32): ~Sendable {   // only this module makes one, and it stays on its thread
    deinit { unsafe { platform_gpu_free(id) } }   // the C call is unsafe; code that uses GpuBuffer never is
}
```

**Decision.** Calling C is `unsafe`, exporting a function to C is an unverified promise about its name and the signature its C callers use, and C that calls Rayo, that Rayo calls, or that touches Rayo memory carries the obligations of `unsafe` Rayo code; breaking them is undefined behavior. Safety comes from Rayo wrappers, as for any `unsafe` code. The spec defines ([09](09-c-interop.md)):

- how C declarations import, and the C representation of exported Rayo types;
- the runtime mechanics Rayo's own guarantees need when C enters: attaching the thread, entering a section, and what an entry meets in each stage of the runtime's life;
- the three facts Rayo declares about a C function, each in the import config or on an `extern c func`, that change what a call to it does:
    - `parks`: the call can be a checkpoint;
    - `noalloc`: `@noalloc` code may make the call;
    - `stack(n)`: the most stack the function needs, which each call checks is left first, and which a `@c` function type carries too.

**Why.** C can't be checked, so a guarantee at the boundary only moves the trust, and its rules never stop growing. A precise mapping keeps wrappers small.

**Cost.** A careless C caller can break a safe module's invariants. An entry point that must defend itself takes raw forms and converts them with checked conversions, such as `WeakPointer<T>(bits:)` ([03](03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c)).

**Rejected.** Guarding the boundary, such as validating every value C passes on entry, or import facts that make a C function callable from safe code, as Rust 2024's `safe fn` in an `unsafe extern` block does. Each guards one thing C could break in a dozen other ways, and each forces a rule elsewhere in the language.

## D14. Copies are written out: taking a value moves it, a binding of a place borrows it, `copy` duplicates

**Nothing is copied unless the code says so: taking a value from a place moves it, a binding of a place borrows it unless it is declared `owned`, and `copy x` makes a second, independent value.**

**Problem.** Two classic bugs come from copies nobody wrote. `var e = enemies[i]; e.hp -= 10` looks like it damages an enemy, but if the binding copies, it changes the copy. `var chunk = world.chunks[i]` looks like it names a chunk, but it quietly copies kilobytes. And when `var b = a` copies some types and moves others, a reader has to know `a`'s type to know what the line does.

```swift
var e = enemies[i]             // error: a bare 'var' of a place
var target = &enemies[i]       // changes the enemy in place
target.hp -= 10

let chunk = world.chunks[j]    // a borrow: nothing is copied
var spawn = copy chunk.origin  // a copy, written out, although 'origin' is a copyable Vec3
spawn.y += 2                   // the chunk is unchanged
```

**Decision.** Every type follows the same rules ([01](01-values-and-ownership.md#values)):

- **Taking a value moves it.** Only a place the code owns can be moved from. Taking from any other place, such as an element or a global, is an error, and `copy`, `.clone()`, `replace`, `swap` and `take()` are the alternatives ([01](01-values-and-ownership.md#moving-values-out)).
- **A binding of a place borrows it, and a binding of a value owns it.** `let x = place` looks, `var x = &place` changes in place, and `owned var x = place` takes. A bare `var x = place` is an error ([01](01-values-and-ownership.md#bindings)).
- **`copy x` duplicates a copyable value.** It is a `memcpy` of the value's bytes, which never allocates. A move-only type is duplicated by `clone()`, which may.
- **The caller decides between a move and a copy.** For an `owned` parameter, `f(x)` moves and `f(copy x)` copies.
- **Patterns, loops and closure captures follow the same rules.** A pattern part and a `for` binding borrow or own as a binding does, and an unscoped closure's capture list says which captures it moves and which it copies ([01](01-values-and-ownership.md#bindings), [04](04-types.md#iteration), [05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)).

A copyable `const` is one exception: it is a named literal, so taking it makes a new value, while a `let` of it borrows it ([01](01-values-and-ownership.md#moving-values-out)). The others are the operations [01](01-values-and-ownership.md) lists as defined to copy their copyable operands in, such as range operators, and, as D3 says, a `String` made from a literal, which copies the literal's bytes at its first write or growth.

**Why.**

- Both bugs become compile errors whose fix says what the code means: `&` to change the element, `let` to look, `copy` for a snapshot.
- `owned var b = a` means the same for an `Int` as for a `List`, and a move changes the owner, not the bytes.
- `copy` is a keyword because it is always a `memcpy` and runs no user code, so no method can shadow it, and one word serves the expression and the capture list (`[copy x]`). `clone()` is a method, because each type defines it and it may allocate.

**Cost.** Scalars need `copy` for snapshots and second owners, as in `let old = copy e.hp` or `ids.append(copy h)`. Taking from a place is declared `owned`, changing one marks it `&`, and unscoped closures list their captures. A `let` of a place reached through a thread-bound object or a thread-local holds its dynamic access until its last use, so a call in between that changes the object panics; `copy` ends the access at once ([01](01-values-and-ownership.md#bindings)).

**Rejected.**

- Implicit copies of copyable types wherever a value is taken or bound, as in Swift, which hide snapshots and big `memcpy`s.
- An opt-in implicitly copyable marker, such as Rust's `Copy` or Mojo's `ImplicitlyCopyable`, under which `owned var b = a` means different things for different types.
- `var x = place` as an implicit move, as Rust's `let mut` is: it is one character from `var x = &place`, so a missing `&` would empty the place instead of failing to compile.
- A `.copy()` method, which a type's own method could shadow and which can't be a capture-list entry.
- A `copy` parameter convention. Giving a value up or copying it is the caller's choice, and `f(x)` or `f(copy x)` already shows it. What it would promise about dependencies holds for shallow values anyway, and `where return outlives x` states it for the rest ([02](02-views-and-dependencies.md#staying-valid-after-a-parameter-moves-on-outlives)).
- `let` as a move, under which every `let` of a borrowed place, an element or a global would need `copy`.
- Marking a borrowing `let`, as `let x = &place`. `&` would then mean both a shared and an exclusive borrow, and the mark would say little: a `let` is read-only whether it borrows or owns, and where the difference matters, one case is a compile error.

## D15. Parameter conventions are adjectives, function modifiers are verbs

**A parameter is borrowed by default, `mutable` or `owned`. A method is plain, `mutating` or `consuming`, and a closure kind non-`mutating`, `mutating` or `consuming`.**

**Problem.** A parameter can be looked at, changed in place, or kept, and the same three apply to a method's `self` and to what a closure does with its captures. The names have to say which is which, and read well in both places.

```swift
func damage(_ e: mutable Enemy, by amount: Float) { ... }   // how it holds 'e'
func adopt(_ items: owned List<Item>) { ... }
mutating func heal() { hp = 100 }                           // what it does to 'self'
let job: consuming () -> Mesh = { bake(consume input) }     // what it does to its captures
```

**Decision.**

- **Conventions say how a function holds its argument.** It is borrowed (no keyword), `mutable` or `owned` ([01](01-values-and-ownership.md#parameters)). A `mutable` argument is marked `&` at the call.
- **Modifiers say what a function does.** `mutating func` and `consuming func` say it for `self`, and `mutating (…) -> T` and `consuming (…) -> T` for a closure's captures ([05](05-protocols-generics-and-closures.md#functions-and-closures)).
- **Bindings mirror the conventions.** A `let` of a place looks, as a borrowed parameter does, and `&` marks a place lent for change in a binding as in a call (D14, [01](01-values-and-ownership.md#bindings)).

**Why.** One word per concept in each role, and the pairs line up: `mutable` with `mutating`, `owned` with `consuming`. The parser never has to tell a convention from a closure kind, so `f: owned () -> Mesh` and `f: consuming () -> Mesh` read differently at a glance. `mutable` says what the borrow allows, not that the callee sees the caller's storage: a bitfield lends a temporary that is written back ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)).

**Cost.** Each concept has two words, one per role. `mutable` also begins the type `mutable any P`, so the `mutable` convention on a shared existential view is written `mutable (any P)` ([13](13-grammar.md#parentheses-and-conventions-in-types)).

**Rejected.**

- `inout`, from Swift, which describes copy-in, copy-out, not a borrow, and would be a third spelling next to `mutating` and `&`.
- `consuming` as both convention and modifier, which makes a parameter read as an action.
- `mut` and `ref`, terse where the rest of the language spells words out; `ref` also names a kind of reference, not a way of holding an argument.

## D16. One `Sendable` contract for crossing threads, and objects that are thread-bound unless declared concurrent

**A value may reach another thread only if its type is `Sendable`, which the compiler derives. An object is bound to the thread that made it unless it is declared concurrent, and then its lock is built in, or it is lock-free and never locked.**

**Problem.** Exclusivity and the lending rules (D9) can't see two things: a link the checker can't follow, such as a weak pointer moved into a thread's body, and a type that is safe only on one thread, such as an OpenGL texture id. Without a contract, every object's checks must synchronize, and a thread-affine C resource is safe only by discipline.

```swift
let mixer = ConcurrentUniquePointer(AudioMixer())
let m = mixer.weak()                            // Sendable
Thread.start { [copy m, copy clip] in m.lock { $0.play(clip) } }   // waits while another thread uses the mixer

struct Hud(var root: WeakPointer<Widget>)
Thread.start { [move hud] in draw(hud) }       // error: 'Hud' isn't Sendable
```

**Decision.**

- **One marker, `Sendable`.** It is derived as `Copyable` is, and required of everything code on another thread can reach ([07](07-concurrency.md#what-may-cross-threads-sendable)). `~Sendable` opts a type out, and `unsafe Sendable` is an unverified promise.
- **Thread-bound objects by default.** `UniquePointer<T>` and `WeakPointer<T>` aren't `Sendable`, so their access marks need no synchronization, a conflict panics, and the `deinit` runs on the home thread ([03](03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)).
- **Concurrent objects say so in the type.** `ConcurrentUniquePointer<T>` and `ConcurrentWeakPointer<T>` have the lock built into the object: `p.lock { … }` for exclusive access and `p.read { … }` for shared. A conflict on one thread panics, and a conflicting access from another thread waits. `lockFree:` makes an object that is never locked, whose value is `Frozen` or `Synchronized` and whose reads take no lock ([03](03-handles-and-objects.md#objects-shared-across-threads-concurrentuniquepointert)).

**Why.**

- Most objects never leave their thread, so they pay nothing for threads. The ones that cross say so in the type, where the cost of a lock belongs.
- Contention between threads is normal and should wait; a conflict on one thread is a bug and should panic (D10).
- With the lock in the object, a shared mutable object needs no wrapper type, and every access still names its kind at the call.
- One marker is enough: outside thread-bound objects, which aren't `Sendable`, whatever a shared borrow can change synchronizes itself. A type that may move to another thread may also be shared with one, and the one kind that could be shared but not moved, a lock guard, stays off other threads entirely ([02](02-views-and-dependencies.md#lock-guards-are-released-on-the-thread-that-took-them)), so Rust's split between `Send` and `Sync` has nothing to separate.

**Cost.**

- Generic code that sends a `T` to another thread states `T: Sendable`.
- Two pointer kinds to choose between.
- A thread-bound object's `deinit` may wait for its home thread's next outermost section entry, and a thread's objects end at its teardown, which a thread still running at exit, or a C thread that exits without detaching, never reaches ([07](07-concurrency.md#global-state)).

**Rejected.**

- Separate `Send` and `Sync` markers, as in Rust, which double what generic signatures state.
- Atomic checks on every object, with no contract: every object pays for threads, and a cross-thread conflict panics where it should wait.
- Run-time home-thread checks alone, which surface in testing a mistake the compiler can reject.
- A lock as a separate wrapper, `ConcurrentUniquePointer<Mutex<T>>`: correct, but the wrapper would appear in every signature for the common case.

## D17. Literals take their type by protocol, and allocate only where the type is written; an `Array` is inline, a `List` grows

**A type takes a literal by conforming to a literal protocol. A literal converts through a conformance that may allocate only where the type is written at the literal, in the declaration's annotation or an `as`. An array literal with no context is an inline `[N of T]`.**

**Problem.** Code wants `[1, 2, 3]` for vectors, matrices, masks, tables and lists, and each type that takes it should be able to say so, without a compiler special case per type. In Swift a literal becomes any conforming type wherever one is expected, so `spawnAll([a, b])` can allocate a heap array with nothing at the call saying so, and a variadic literal initializer builds a heap array even for a three-lane vector.

```swift
let v: Vec3 = [1, 2, 3]                   // Vec3 conforms: exactly 3 elements, checked at compile time
let mask: LayerMask = [.player, .enemies]
let xs = [3, 4, 5]                        // [3 of Int]: inline, no allocation
let ys: List<_> = [3, 4, 5]               // allocates, and the annotation says so
let zs = [3, 4, 5] as List<_>             // the same, with 'as'
spawnAll([a, b])                          // error: the List parameter would allocate unseen
```

**Decision.**

- **Five protocols take literals.** They are `ExpressibleByArrayLiteral`, `ExpressibleByDictionaryLiteral`, `ExpressibleByStringLiteral`, `ExpressibleByIntegerLiteral` and `ExpressibleByFloatLiteral` ([04](04-types.md#literals)).
- **A conformance that may allocate applies only where its type is written at the literal.** A `@noalloc` one, such as `Simd`'s, applies wherever the type is expected, and so does one whose literals convert at compile time, such as `Name`'s ([04](04-types.md#literals)).
- **An array literal arrives as an owned `[N of Element]`.** Its count is known at compile time, so a fixed-size type rejects a wrong count at compile time.
- **Names follow what the type does.** `Array<T, N>`, written `[N of T]`, is the inline array, whose length is part of its type. `List<T>` grows on the heap, and `InlineList<T, N>` grows up to `N` elements stored inline. A literal with no context makes an `Array`.

**Why.** Every allocation a literal of these protocols makes is visible where the literal is: a reader sees `List` next to the literal, as in `[a, b] as List<_>`, and never has to look up a parameter's type to learn that a call allocates. A type that can take a literal without allocating takes it anywhere, as std's `String` does (D3), so `names.append("grunt")` needs no ceremony. The literal protocols are ordinary conformances, so user types such as masks and matrices get the same syntax as std's. `Array` meaning the fixed, inline kind matches what an array is in C, and keeps "array" from meaning two things.

**Cost.** A literal passed to a `List` parameter, returned as one or assigned to an existing one says `as List<_>`.

**Rejected.**

- Swift's rule: a literal becomes any conforming type wherever one is expected, which hides allocations behind a literal.
- No allocating conformances, with `List([…])` the only way: it makes `let xs: List<Int> = [1, 2, 3]` an error although the type is right there.
- `[T]` as sugar for the growable type: brackets would mean an inline array in `[N of T]` and a heap one in `[T]`.

## D18. A struct's stored fields are its primary initializer; every other `init` delegates

**A struct's header lists its stored fields, in layout order, and is its primary initializer. The body holds behavior. Every other `init` computes its arguments and calls `self.init(…)`.**

**Problem.** In Swift a struct's fields are declared among its computed properties and methods, and each `init` assigns them one at a time. An `init` that throws halfway leaves a value partly built, whose assigned fields must then be destroyed one by one, and a type with a `deinit` could never run it on a value that was never whole.

```swift
public struct Fraction private init(let num: Int, let den: Int) {   // the layout, and the only way to build one
    public init(_ num: Int, over den: Int) {
        precondition(den != 0, "zero denominator")
        self.init(num: copy num, den: copy den)
    }
}
```

**Decision.** The rules are in [04](04-types.md#initializers):

- **The header lists every stored field.** `private init(…)` keeps the primary initializer inside the module.
- **A secondary `init` calls `self.init(…)` at most once on every path, and exactly once on every path that returns the new value.** Before that call, `self` doesn't exist.
- **Header entries are fields, not parameters.** Each is taken `owned`, and none takes a parameter convention.
- **Unions and enums keep their bodies.** A union is built from one member, and an enum from one case.

**Why.**

- The header is the layout: one list, in order, which C interop, packing, reflection and serialization all read.
- No value is ever half-built, so an `init` that fails destroys only its locals or a whole value.
- A private primary initializer gives an invariant one gate, which every other module passes through a checking secondary one.

**Cost.** Fields move out of the body, and a `static for` that generates fields moves into the header.

**Rejected.**

- Swift's body fields, which each `init` assigns one at a time, for the reasons above.
- Body fields with an implicit memberwise initializer that every other `init` calls: the same semantics, but the fields stay mixed with behavior, and the implicit initializer has no declaration to make private.
- Kotlin's plain constructor parameters and body properties with initializers: stored fields in two places, so the layout isn't one list.

## D19. `when` and `if` are expressions, and there is no ternary

**`when` matches a value against patterns with `where` guards. `when` and `if` / `else` produce values, and the value of an `if` or `when` block is its last expression.**

**Problem.** A value chosen by cases is common: a label for a state, a damage table, a sign. With `switch` and `if` as statements, each case assigns a variable declared before it, or returns, and a one-line choice needs a ternary, a second syntax for the same thing.

```swift
let label = when state {
    .idle -> "idle"
    .chase(let t) where t.isBoss -> "fleeing"
    else -> "busy"
}
let bonus = if boosted { 10 } else { 0 }
```

**Decision.** The rules are in [04](04-types.md#matching-with-when-and-choosing-with-if):

- **`when subject { pattern -> body }` runs the first arm that matches.** It is exhaustive and never falls through. Without a subject, each arm is a `Bool` condition.
- **`when` and `if` / `else` are expressions.** Each block's value is its last expression. The position they stand in applies to the arm that runs, so a binding still says whether it borrows, moves or copies (D14).
- **There is no ternary operator.**

**Why.**

- One construct serves both uses, a statement and a value.
- `->` arms and an `else` arm read the same as `if` / `else`, and dropping the subject gives a condition chain with no second construct.
- Without the ternary, a `?` after an operand always means optional chaining, and the grammar needs no whitespace rule to tell the two apart.

**Cost.** A one-line conditional value is longer than `c ? a : b`. A line in a `when` body that reaches `->` starts a new arm, so a function type after `as` there is parenthesized ([13](13-grammar.md)).

**Rejected.**

- Swift's `switch` with `case` labels, as a statement or as an expression: labels made for statements, and a single-expression limit on each case when it is used as a value.
- A ternary beside `if` expressions: two spellings of one thing.

## Open questions

### Q1. Inline capture budget for `Closure`

The spec fixes a `Closure` at 32 bytes, with up to 24 bytes of captures inline and larger captures in an allocated context ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)). Should that size change? A bigger `Closure` allocates less often and costs more in every struct that stores one, and a smaller one the reverse. **Decided by** measurements on real code.

### Q2. `SoA<T>`: builtin or std type

`SoA<T>` stores each field of a struct in its own buffer, and the spec makes it builtin ([04](04-types.md#struct-of-arrays-soat)). Could it be a std type? As one built with generated declarations ([10](10-compile-time.md#generating-declarations)), its columns can be generated fields, but its row views need a projection per field that behaves like a field of the row. **Decided by** a prototype of generated row views.

### Q3. Generic code-size control

Rayo always specializes generics and never calls them through a witness table implicitly ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). Does it need an explicit `@shared` opt-out that uses witness tables for cold generic code, or is the code size of full specialization acceptable? **Decided by** generic code size in practice. **Leaning:** none; if added, an explicit opt-out, never a default.
