# Safety argument

The [spec](../spec/README.md) defines Rayo. This document checks its safety claim by tracing the rules to five invariants. It is an argument about the design, not a source of language rules or a mechanically verified proof.

```swift
var lines = List<StringView>()
splitLines(source.view, into: &lines)   // rule 4: 'lines' takes on what source.view carries: 'source', shared
source.append("x")                      // error: changes 'source' while 'lines', used below, borrows it
print(lines[0])
```

**Safe code has no undefined behavior** ([01](../spec/01-values-and-ownership.md#tiers-of-checking)). Each rule of the spec keeps one or more of the five invariants below, which together make that so. The argument has three steps:

1. **The invariants.** It lists the undefined behavior that 10 defines, and five invariants that rule out the rest ([below](#the-invariants)).
2. **The rules.** Each subchapter takes one part of the language and shows how its rules keep the invariants.
3. **The boundary.** It ends with the promises of `unsafe` code and C that the argument relies on ([The unsafe boundary](safety-argument/types-and-boundaries.md#the-unsafe-boundary)).

**The example above shows one step.** `append` may move the text to a larger buffer and free the old one, which `lines` still views. The compiler finds the conflict because `lines`' dependency set names `source`, which owns that text. That every value's set accounts for the memory it views is the property called Covered ([Covered](safety-argument/dependencies.md#covered)).

## The invariants

**The undefined behavior that 10 defines is one of these** ([10](../spec/10-errors-and-safety/unsafe-code.md#raw-accesses)):

- an access outside a live allocation;
- a misaligned access;
- a read of an invalid value;
- a data race;
- a write to memory Rayo treats as immutable;
- the failure of a memory-safety check that `unchecked` removed ([10](../spec/10-errors-and-safety/checks-and-build-modes.md#unchecked-blocks)).

**Safe code never meets the last.** It has no `unchecked` block, and its memory-safety checks are on in every build ([10](../spec/10-errors-and-safety/checks-and-build-modes.md#check-levels)).

**Five invariants rule out the rest:**

- **Live.** Safe code accesses memory only inside an allocation, while the allocation is live ([10](../spec/10-errors-and-safety/unsafe-code.md#allocations)), so nothing it reads or writes has been freed or reused. No access falls outside a live allocation.
- **Valid.** A place that safe code reads, lends or destroys holds a valid value of its type, at an address aligned for it. So nothing safe code reads, lends or destroys is misaligned, and no read finds an invalid value.
- **Exclusive.** While a mutable access to a place is live, nothing reaches an overlapping place except through it. While a shared access is live, nothing writes the place, except a `Synchronized` value through its own synchronization. Read-only data, which holds every frozen `const`, and a `Frozen` value behind a `Shared` or a `LocalShared` are shared for good, so nothing writes the memory Rayo treats as immutable.
- **Owned.** A value has one owner, except a reference-counted value, which its owners share. It is destroyed at most once, and used neither after its destruction nor after it moves out.
- **Race-free.** Two accesses to the same bytes on different threads, at least one a write, are ordered by happens-before ([07](../spec/07-concurrency/synchronization.md#atomics-and-locks)), unless both are atomic accesses of the same size at the same address. So no two accesses form a data race.

**These are what 10 asks of `unsafe` code, stated for all code** ([10](../spec/10-errors-and-safety/unsafe-code.md#what-unsafe-code-upholds)). The subchapters show that safe code keeps them. They assume that `unsafe` code and C keep them too, and that both keep the promises the spec lets them make ([The unsafe boundary](safety-argument/types-and-boundaries.md#the-unsafe-boundary)).

**The static rules also rest on one property of dependency sets, Covered**: a value's set accounts for all the memory it views ([Covered](safety-argument/dependencies.md#covered)).

## Subchapters

- [Ownership, borrows and exclusivity](safety-argument/ownership-and-borrows.md)
- [Dependency invariants](safety-argument/dependencies.md)
- [Runtime values and concurrency](safety-argument/runtime-and-concurrency.md)
- [Types and safety boundaries](safety-argument/types-and-boundaries.md)
