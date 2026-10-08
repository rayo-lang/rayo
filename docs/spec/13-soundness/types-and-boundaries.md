# Types and safety boundaries

[13 · Soundness](../13-soundness.md)

## Types and layout

**This section keeps Valid.** The bytes safe code reads as a type are always a value of that type, at an address aligned for it.

- **`Pod` means every bit pattern is valid and nothing is owned** ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). Its fields are visible and not `unsafe`, so bytes can't forge a value whose invariant a `private init` or an `unsafe` field guards, and `@pod` is a promise.
- **Padding is uninitialized, so no cast reads it as data** ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). Each cast needs padding-free types:
    - a bit cast, a padding-free source;
    - a shared span cast, a padding-free source type;
    - a mutable span cast, both types padding-free, since a store through a padded type leaves its padding unspecified while other views still see the source type.
- **Union reads** ([04](../04-types/enums.md#untagged-unions)). Writing a whole member is safe. Reading needs every member `Pod`, none `unsafe`, and the union padding-free, so whatever a write left is a valid value of the member read. Members are copyable, so nothing needs to know which one to destroy.
- **Niches** ([04](../04-types/enums.md#optionals)) are bit patterns a type never uses, in which an optional stores its `nil`. None lies in a `Synchronized` value, whose bytes other threads write while a tag is read with a plain load, or in a bitfield, whose width may leave no room.
- **Under-aligned places are used only by value** ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)), through aligned temporaries, so no view of one exists. A view would load or store at a misaligned address, which is invalid and faults on some targets. Generic code takes the safe bound, and a packed struct holds no `Synchronized` value, which needs its alignment.
- **A whole store may write padding**, so a `TrailingArray`'s header, whose tail padding may hold elements, is written field by field, and a `Synchronized` value never shares bytes with either side ([04](../04-types/data-layout.md#variable-sized-structs-trailingarray)).
- **Text is UTF-8.** String ranges are checked on scalar boundaries ([04](../04-types/collections.md#strings)), so every string holds whole UTF-8 sequences, as a valid one must ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)).
- **Arithmetic** ([04](../04-types/numbers-and-math.md#integer-overflow-division-and-shifts)). An overflow that wraps gives a wrong value, never an invalid one, and the next bounds check still catches a wrong index. Division by zero and converting NaN or an out-of-range float are memory-safety checks, since their failure, unchecked, is undefined behavior ([10](../10-errors-and-safety/checks-and-build-modes.md#the-checks)).
- **Imports keep C's meaning** ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)):
    - a struct Rayo can't lay out exactly imports as `@opaque`;
    - a zeroing `init()` exists only where all-zero bytes are valid;
    - an enum is closed only where its header says so, holding any value of its underlying type otherwise, since C lets an enum object hold any value of that type.

## Compile time and reflection

**Compile-time evaluation and reflection keep the invariants as ordinary code does.** Evaluation builds values that run time trusts, and reflection reaches fields without naming them.

- **Evaluation checks what run time trusts** ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)): every raw access and every memory-safety check an `unchecked` block removes, on one thread. So an access outside its allocation, into freed memory, misaligned or of an invalid value is a compile error.
- **A frozen value is never written or destroyed** ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)), since it lies in read-only data. So it:
    - is `Frozen` with no bookkeeping, and `TrivialFree`;
    - holds nothing that exists only at run time, such as a weak pointer or an allocator id;
    - holds no stale owning value;
    - points only at memory that freezing copies, or at immortal data;
    - views only read-only data, since freezing follows only raw pointers, and any other view would still point at compile-time memory.

  It is `Sendable`, since every thread may read it.
- **Reflection grants nothing a name doesn't** ([09](../09-compile-time/reflection.md#reflection-and-access-control)): the same visibility, `unsafe` fields, union reads and moves out, and `T.construct` calls the primary initializer. So a `private init` keeps guarding its type's invariants. A reflective projection is a storage or access-bound projection exactly as the field is ([09](../09-compile-time/reflection.md#what-reflection-can-read)).
- **Generated declarations are checked as written ones** ([09](../09-compile-time/declaration-generation.md#generated-members-are-checked-per-instantiation)), and generic code takes them at the safe bound ([Generic code and existentials](runtime-and-concurrency.md#generic-code-and-existentials)).

## Checks and panics

**A run-time check keeps its invariant only where it runs, and only if a failure leaves nothing unsound behind:**

- **Memory-safety checks are on in every build** ([10](../10-errors-and-safety/checks-and-build-modes.md#check-levels)), and only `unchecked` code, which isn't safe code, removes them. Each fails before the access it guards.
- **A diagnostic check guards nothing memory depends on**: with it off, a wrong value still meets every memory-safety check.
- **A panic never returns and never unwinds** ([10](../10-errors-and-safety/panics.md#what-a-panic-does)), so no frame's borrows end early, no `deinit` runs on a half-changed value, and work lent from the panicking thread still finds its memory. Other threads may run briefly, which `unsafe` code allows for by leaving shared state valid wherever it can panic.
- **No frame is written past its stack's end** ([10](../10-errors-and-safety/panics.md#what-panics)): every function checks its stack on entry, and every call into C checks the need its target declares.

## The unsafe boundary

**The argument above assumes that `unsafe` code and C keep the invariants for their own accesses** ([10](../10-errors-and-safety/unsafe-code.md#what-unsafe-code-upholds), [08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold)). It also rests on these promises, each of which some step relies on, so a broken promise breaks that step:

| Promise | What relies on it |
| --- | --- |
| A view made from a raw pointer reaches live, aligned, valid places, with the dependencies its signature states ([02](../02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in), [10](../10-errors-and-safety/unsafe-code.md#values-views-and-threads)) | [Covered](dependencies.md#covered) |
| A mutable view built from a raw pointer changes only what its exclusive inputs own or carry ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#mutable-views)) | [Mutable views](dependencies.md#mutable-views) |
| A value kept through a raw pointer is held in a type that says what it holds, and what is handed out of that storage borrows only what the call gives ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#shallow-values)) | [Rules 3 and 4](dependencies.md#rule-3) |
| A shallow value's bytes viewed with `ptr(to:)` never reach a sealed type ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#shallow-values)) | The shallow rule ([Rule 3](dependencies.md#rule-3)) |
| A storage projection's yield through a raw pointer lies in storage the named parameter owns or views ([02](../02-views-and-dependencies/projections-and-accessors.md#storage-projections)) | [Projections](dependencies.md#projections-and-accessors) |
| `unsafe Sendable` ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)) | [Threads](runtime-and-concurrency.md#threads) |
| `unsafe Synchronized` ([07](../07-concurrency/synchronization.md#the-synchronized-contract)) | [Threads](runtime-and-concurrency.md#threads), Exclusive |
| `unsafe Frozen` ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)) | `Shared`, `LocalShared`, freezing |
| `PlainDeinit` ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)) | [Destruction as a use](dependencies.md#destruction-as-a-use) |
| `AllocatorImpl` ([06](../06-memory-and-allocators/allocator-implementations.md#what-conforming-promises)) | [Memory and allocators](runtime-and-concurrency.md#memory-and-allocators) |
| `@pod` ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)) | `Pod` |
| The library's lending promise ([07](../07-concurrency/thread-work.md#the-librarys-promise)) | Borrows lent for a call ([Threads](runtime-and-concurrency.md#threads)) |
| `Box.adopt` takes back a leaked `Box<T>` once ([06](../06-memory-and-allocators/owning-values.md#owning-boxes)) | Owned |
| `@export`, `extern c func` and the rules of an `import c` config block, each an assertion about C ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)) | Valid, the stack check |

**What `unsafe` code allows for is part of the same boundary** ([10](../10-errors-and-safety/unsafe-code.md#aliasing-and-skipped-deinits)): memory has no declared type, and a `deinit` may never run.

**No `unsafe` call is hidden** ([10](../10-errors-and-safety/unsafe-code.md#what-needs-unsafe)), so every promise is made at a visible `unsafe` site. A `@safe` module has no such site ([10](../10-errors-and-safety/unsafe-code.md#safe-modules)), so it makes no promise and is sound given the modules it calls.
