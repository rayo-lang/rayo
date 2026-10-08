# Checks and build modes

[10 · Errors and safety](../10-errors-and-safety.md)

## Check levels

```swift
let v = borrow verts[i]   // bounds check: without it, a bad index would read memory outside the buffer
let n = a + b             // overflow check: without it, the sum wraps, which is a wrong value but memory-safe
```

**Checks come in two classes:**

- **Memory-safety checks**, bounds checks among them, make safe code sound. They are on in every build, and only `unchecked` code can strip them ([below](#unchecked-blocks)).
- **Diagnostic checks** catch logic bugs whose failure is still memory-safe, such as wrapping arithmetic. With one off, a wrong value still meets every memory-safety check, as a wrapped index meets the next bounds check ([13](../13-soundness/types-and-boundaries.md#checks-and-panics)).

**Each diagnostic check is on or off where code is written.** The innermost of these decides it:

- an enclosing `@checks` ([below](#choosing-checks-for-a-module-or-a-scope));
- the module's settings;
- the build mode's default ([below](#build-modes)).

An enclosing `unchecked` block turns every one off ([below](#unchecked-blocks)). `target.checks` holds those that are on ([09](../09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation)).

### Choosing checks for a module or a scope

```swift
@checks(.all) func accumulate(_ total: mutable Int, _ xs: Span<Int>) { … }   // overflow checked here, even in release
@checks(.none) do { for x in xs { sum += x } }                            // diagnostics off in this block only; bounds stay on
```

**Diagnostic checks can be chosen per module and per scope.**

- **Per scope**, for a function, a type's members or a `do` block, with `@checks(…)`. It takes `.all`, `.none`, or a set of the diagnostic checks, which are `.overflow` and `.assert` ([below](#the-checks)), as in `@checks([.overflow])`. It sets exactly those on for its scope, replacing what encloses it.
- **Per module**, with the same values, in the build's settings ([09](../09-compile-time/attributes-and-runtime-data.md#what-a-build-declares)).
- **In `@safe` modules too**, since they only choose diagnostic checks.

### `unchecked` blocks

```swift
unchecked {                        // bounds and the table's other checks off here
    for i in 0..<n { dst[i] = src[i] * k }
}
```

**An `unchecked` block removes every check in the table below that its code performs.** Its code is the code written inside it, and the bodies of the `@inline` functions it calls, such as a collection's subscript, which become part of it ([11](../11-compilation-model.md#functions-that-are-never-calls-inline)).

**It leaves these in place:**

- the checks of the other functions it calls;
- the panics that the table doesn't list ([What panics](panics.md#what-panics));
- synchronization, since a lock and an atomic operation are the operation itself;
- the memory ordering of a check that also orders memory, as a single-sided queue's side check does ([07](../07-concurrency/synchronization.md#queues-and-channels)). Only its failure test is removed.

**A removed diagnostic check acts as where it is off, and any other removed check's failure is undefined behavior.** So an overflow wraps or truncates, and `assert` doesn't evaluate its condition.

### The checks

| Check | Class | `debug` | `release` |
| --- | --- | --- | --- |
| Indexing and slicing bounds, and string ranges on Unicode scalar boundaries | memory safety | on | on |
| Stack space, on entry to each function and before each call into C | memory safety | on | on |
| Thread-bound object: liveness, conflicting accesses, and destruction under an access | memory safety | on | on |
| Thread-local: initialized, not destroyed, and conflicting accesses | memory safety | on | on |
| Opening an owning value whose storage a reset or an unregistration invalidated | memory safety | on | on |
| Safety counts: reader, pin, owner and allocator-use counts | memory safety | on | on |
| `Slice` of a locked blob or `List`: current length and alignment, or current count | memory safety | on | on |
| Taking a `Mutex`'s or an `RwLock`'s exclusive access on a thread that holds either kind, or either kind on a thread that holds the exclusive one | memory safety | on | on |
| Single-producer and single-consumer queues: overlapping calls on one side | memory safety | on | on |
| Reading a global before its initializer has run | memory safety | on | on |
| Entry from C before startup or after shutdown | memory safety | on | on |
| Polling a finished task | memory safety | on | on |
| Integer division and remainder by zero, and float-to-integer conversion of NaN or an out-of-range value | memory safety | on | on |
| Integer overflow on `+ - *`, unary `-`, `Int.min / -1`, unlabeled integer conversions whose value doesn't fit, and imported bitfield writes that don't fit the width ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)) | diagnostic | on | off: wraps or truncates ([04](../04-types/numbers-and-math.md#integer-overflow-division-and-shifts)) |
| `x!` on `nil`, and `try!` on an error | memory safety | on | on |
| `precondition` | memory safety | on | on |
| `unreachable()` reached | memory safety | on | on |
| `assert` | diagnostic | on | off |

**Division by zero, the float-to-integer conversions, `!`, `try!` and `unreachable()` count as memory safety, since, unchecked, their failure is undefined behavior.** `precondition` counts as memory safety since `unsafe` code may rely on it.

## Build modes

**A build is in one of two modes: `debug`, for developing a program, and `release`, for shipping it.** Each sets the default for the diagnostic checks, as the table above gives it ([above](#the-checks)): `debug` turns every one on, and `release` every one off. A build that names no mode is a `release` build.

**The mode sets nothing else the language defines.** Optimization and debug information are left to the toolchain, which may tie them to the mode. Neither changes what a safe program computes ([11](../11-compilation-model.md#what-the-language-leaves-open)).
