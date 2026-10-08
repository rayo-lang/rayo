# C interop, performance and hot reload

[Hard cases](../hard-cases.md)

## E. C interop

**Every crossing between Rayo and C is unsafe by definition.** C has the obligations that `unsafe` Rayo code would have in its place ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold)), and a C header can't say that a pointer outlives a call, or that a buffer holds `n` elements ([08](../08-c-interop/imports-and-inline-c.md#calling-imported-functions)). So these cases are exempt from **Forced unsafe** on the C side. They check two things: the mapping is precise enough to bind real C APIs, and the Rayo wrapper's `unsafe` part stays small, with obligations that are easy to state and keep.

### E1 · C holding pointers into Rayo memory

**A C library stores a `void* user` per registered item, and calls a callback on its own threads with two of those pointers**, as a physics library's contact callback does. Some items are elements of a `StablePool`, which the program later replaces whole by assigning it a new one, and some are objects allocated in an arena that is later reset. Separately, a global `let` `StablePool` has one of its elements pinned for C. That pool is initialized at startup, never placed in read-only data, since its pin counts are written at run time ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)).

```swift
pool = StablePool()      // assigns a new pool: the old one is destroyed while C may still hold its elements' addresses
```

- **Must accept** an idiom whose `unsafe` part is only the C calls. State what the Rayo side must provide: stable addresses of whatever `user` points to, and thread safety.
- **Must hold:** C's address stays valid for as long as its pin lives, and replacing the pool or resetting the arena never runs the element's `deinit` or frees its memory before C is done with it. State what a reset does while a pin into the arena lives. The global element's address is valid for the whole run.
- State what C sees when Rayo code assigns a new value to a pinned element.
- **Must accept** moving the `Pin` of a `Sendable` `StablePool` element to an I/O completion thread that drops it there.

### E2 · C types with unusual layouts (also A22)

**Code imports C types with unusual layouts and uses them from safe code**, some from several threads at once. They include structs with bitfields, anonymous unions, flexible array members, packed structs, and `enum`s with explicit negative values:

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

A packed struct can put a field at a misaligned address, where a load or store of the field's type is invalid ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)). And C lets an enum hold any value of its underlying type, not only its cases ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)).

- **Must accept** each of these:
    - each type imported with its exact layout;
    - reading either member of a union of same-size plain-data members;
    - reading a file header that contains such a union as plain bytes;
    - a C enum the header doesn't declare closed holding any value of its underlying type, with no undefined behavior, including in a `@safe` module that matches it with `when`.
- **Must accept** imported structs under the borrow rules: union members read and written by value, and two closures of one `join` writing bitfields in different C memory locations of one struct, or a bitfield and a neighboring field.
- **Must accept** reflection, serialization and `SoA` over an imported struct with bitfields, and a `@packed` struct conforming to a protocol whose `read`/`modify` property its under-aligned field provides, used from generic code.

### E4 · Exporting data and functions to C callers

**Code in another language binds to Rayo through its generated C header**: it reads a `List` of structs and calls Rayo functions with strings.

- The generated header must be enough to bind to.
- **Must accept** an idiom for reading the list whose obligations on the caller's side are easy to state and keep, even when the list's storage came from an arena that is later reset or a heap that is later unregistered.
- The caller calls back an `@export` function that takes a span and a weak pointer to the list, whose body appends to the list. State what the caller may pass as the span.
- **Must accept** an `@export` function that builds a `String` in the current thread's scratch arena and gives the caller an owner that stays valid until the caller frees it through the header's function.

### E5 · SIMD values across the boundary

**Call a C function that takes a vector type such as `__m128` or `float32x4_t` by value.**

- **Must accept** `Simd<Float, 4>` passed directly, with a defined ABI mapping.

### E6 · Mistyped references from C

**C holds references to Rayo objects of different types as `uint64_t`s, and may pass the wrong one back to an `@export` function.**

- **Must accept** an entry point that defends itself against that mistake, so the wrong object is never accessed as the other type, in any build, with no `unsafe` in the Rayo code.
- **Must accept** C holding references to objects of different types as `uint64_t` and passing them to one Rayo function that takes any object conforming to a protocol.
- **Must accept** a `@c func` callback taking two `WeakShared<T>`s, registered with a C library whose callback type takes two `uint64_t`s, and that calls it on its own threads.
- **Must accept** the same with `WeakPointer<T>`, for a library that calls back on the thread that drives it.
- State what the C library must uphold in each.
- **Must accept** `Handle` bits that C passes back as a `void* user` which addresses nothing, converted back only by `unsafe` code.

### E7 · C code that needs a large stack

**A C library's function recurses deeply, and a plugin's callback is documented to need 1 MiB of stack.** Running out of stack panics before anything is written past the stack's end, so a call into C first checks that the stack its target needs is left ([08](../08-c-interop/imports-and-inline-c.md#the-stack-a-c-call-needs)).

- **Must accept** calling each, within C's obligations, by declaring its need where the function or the pointer type is declared.

---

## F. Performance

**No build of a program does work at run time that its source doesn't show**, beyond the calls the language makes for it ([11](../11-compilation-model.md#runtime-costs)). These cases test that promise in hot loops and dispatch, what monomorphized generics cost in code size, and that arithmetic has one defined result on every target.

### F1 · Vector math in unoptimized builds

**A loop over many values does vector arithmetic**, such as this:

```swift
pos += vel * dt          // vector arithmetic on each value
vel = lerp(…)            // a call to a small math function
```

- **Must accept** unoptimized code with no function call per operation and no hidden check beyond bounds checks ([11](../11-compilation-model.md#runtime-costs)).
- **Must accept** generic vector code over `T: VectorSpace` whose requirement calls reach `@inline` operators, each running in place in every build, and `@inline` functions that call each other in a cycle through a generic witness.

### F2 · Generic code size

**A generic type such as `List<T>` is instantiated for hundreds of element types.** Generics are monomorphized: each set of type arguments gets its own compiled copy ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#instantiation)).

- State the code-size strategy and its compile-time cost.
- State whether shared (non-monomorphized) instantiation is possible.

### F3 · Many types behind one interface

**Many types that conform to one protocol are run each iteration through the protocol**, as an engine's render passes are. The second criterion passes each value, held as an existential, to this generic function:

```swift
func run<T: P>(_ x: mutable T, …)      // generic over the protocol's conforming types
```

- **Must hold:** no allocation per iteration and no hidden boxing, and the dispatch cost is visible in source.
- **Must accept** passing each `mutable any P`, or each `Box<any P>` element's `&b.value`, to `run` above. State how that call runs, given that generics are monomorphized, and its code-size cost.

### F4 · Bounds checks in hot loops

**A kernel indexes `src[i + k]` inside a nested loop.** Bounds checks are memory-safety checks, on in every build, and only `unchecked` code strips them ([10](../10-errors-and-safety/checks-and-build-modes.md#check-levels)).

- Show how to reach check-free code: safe if possible, `unchecked` if not, with the audit surface stated.

### F5 · Bit-identical results on every target

**A computation must give bit-identical results on every machine**, as a lockstep simulation does when it compares a hash of its state across machines with different platforms and compilers. It uses `Float` and `Simd` math with `a * b + c` patterns, square roots and conversions, and calls whose arguments have side effects, such as this one:

```swift
spawn(at: rng.next(), heading: rng.next())    // each argument draws the next random number
```

- **Must accept** bit-identical state on every target, under every toolchain and in every build mode, from the language's rules alone. Name the rule that fixes each result.
- State what the program must avoid or supply itself to stay deterministic, such as its own `sin`.

### F6 · Integer and float edge cases

**A hash function meets the edge cases of integer and float arithmetic.** It divides by a value read from a file, negates and divides `Int.min`, and shifts by a count computed at run time that can reach the bit width. It also converts a `Double` read from the file to `Int`, NaN included, or to a `Float` out of its range, converts a `UInt` count to `Int32`, and shifts negative values and `Int.max` left. Targets' conversion instructions disagree on some of these, such as NaN converted to an integer ([04](../04-types/numbers-and-math.md#conversions)).

- Every result must be defined in every build, a value or a panic, never undefined behavior, and the cost in `release` builds ([10](../10-errors-and-safety/checks-and-build-modes.md#build-modes)) stated.

---

## G. Hot reload: a tool the language must not rule out

**A hot reloader swaps code and migrates live state while a program runs.** It is a tool built on a runtime and toolchain layer that the spec doesn't define ([11](../11-compilation-model.md#what-the-spec-defines)), so these cases don't ask how it works. They check that the language keeps it possible: each names language properties a reloader would build on.

- **Solved** means every property the case names holds in the spec.
- A rule of the spec that breaks one, such as a way for safe code to keep the address of a value it doesn't own, is the finding.

### G1 · Changing a type while values of it are alive

**A field with a default is added to a struct while many values of it are alive**, in a pool inside an object that `main` owns.

- **Must hold:** safe code can't learn a value's address, only immortal data's, unless `unsafe` code or C gives it a raw pointer. Its stored links are these:
    - handles, weak pointers, owners, `Slice`s, `Pin`s, `RawAllocation`s and `Allocator` ids;
    - `StaticSpan`s and `StaticString`s, and `String`s that still use a literal's bytes;
    - `Closure`s and `@c` pointers, which name code;
    - raw pointers, which only `unsafe` code or C makes.
- **Must hold:** a thread with no Rayo frame on any of its stacks holds no borrow and no dynamic access.
- **Must hold:** a type's fields, their layout and their defaults are known to the compiler, and readable through reflection ([09](../09-compile-time.md)).

### G3 · What C holds

**C holds `user` pointers to pinned elements and a `@c` callback pointer, as in E1**, and code in another language binds to a generated header that contains a `@c` struct.

- **Must hold:** every address C can hold is visible in the program, as one of these:
    - a `Pin`;
    - a `RawAllocation`, such as a leaked box's;
    - a `@c` function pointer;
    - an `@export` symbol;
    - a `StaticSpan` or `StaticString`;
    - a `Span`, `MutableSpan` or `StringView` that an exported or `@c` function returns;
    - a `List`, `String` or `TrailingArray` returned to C ([08](../08-c-interop/calling-rayo-from-c.md#ownership-that-crosses-to-c));
    - anything `unsafe` code passed to C.

  A leaked object crosses as its weak pointer's bits, not an address. Every layout C sees is one that a generated header or C's own header declares.

### G4 · Suspended code

**Tasks in a `TaskSet` are suspended, and a `Thread.loop` thread is parked waiting for its next item.**

- **Must hold:** a task suspends only at `await`, holding no borrow and no dynamic access there ([07](../07-concurrency/tasks.md#semantics)). State what a parked thread holds while it waits.

---
