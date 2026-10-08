# Hard cases

**This file is a validation suite for the Rayo spec, the numbered chapters beside it.** Each case names a capability that systems code needs, chosen because a mainstream language forbids it, makes it painful, or makes it unsafe. A case's examples show one instance of the capability, and its criteria hold for every instance. For each case, a validator writes the Rayo code the spec allows and judges it against the case's pass criteria. The spec is the only source of truth: a case that needs a feature the spec doesn't define fails.

The cases test Rayo's governing rule: **no reasonable systems pattern is forbidden**, and each lands in the cheapest of the three tiers of checking that can check it ([01](01-values-and-ownership.md#tiers-of-checking)). The tiers are the compiler, at no run-time cost; a check at each use, in the dynamic tier; and `unsafe` code, which nothing checks. A pattern the compiler can't prove is checked at run time instead, and is never forbidden or forced into `unsafe` for that reason.

## How to validate

**Each case is a capability, with the patterns that exercise it, and a validator grades it with a verdict** (below). The cases test what the rules let code express. Why everything they accept is sound is argued separately ([13](13-soundness.md)).

The cases and criteria use these terms from the spec:

- A **view** is a value that borrows memory something else owns, such as a `Span<T>` of a list's elements or a `StringView` of a string's text.
- A **scoped** value, one whose type conforms to `Scoped`, must stay within the scope that lent it, as every view that borrows memory that can be freed must ([02](02-views-and-dependencies/scoped-values.md#scoped-values)).
- A `Handle<T>` is a small checked index into a pool of `T`s.
- A `UniquePointer<T>` owns one object, and a `WeakPointer<T>` is a checked pointer to it, which other values may store. Both stay on the thread that made the object.
- A `Shared<T>` is a reference-counted pointer to a value that several threads share. That value never changes, or synchronizes itself, as a `Mutex` does. A `WeakShared<T>` is a checked link to such a value that doesn't keep it alive ([06](06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)).
- A **`Sendable`** type is one whose values may reach another thread. The compiler derives it from what the type holds, every `Synchronized` type is one, and a type can opt out with `~Sendable` or promise it with `unsafe Sendable` ([07](07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).
- A **parked** thread is blocked in a wait, such as on a queue or a condition variable.

Each case describes what the code is trying to do, and then lists its pass criteria:

- **Must accept:** the spec must let you write this. The tier it lands in decides the verdict (below).
- **Must hold:** a property the spec's rules must have.
- **Other bullets** are requirements the solution must meet, or questions your report answers (**state**, **show**, **define**, **name**).

For every case, report the **tier** the natural solution lands in, and one verdict:

| Verdict | Meaning |
| --- | --- |
| **Solved** | The pattern is written directly, in the cheapest tier that can reasonably check it, and it meets every pass criterion. |
| **Solved with cost** | It's expressible, but only in a more expensive tier than it should need (a run-time check the compiler could have proven, a copy, a restructuring), or with more ceremony than the same code in C++, C# or Swift. Name the cost. |
| **Forced unsafe** | A pattern that isn't inherently unsafe can only be written with `unsafe`. **This counts as a failure.** Cases marked *(inherently unsafe)* are exempt: there `unsafe` is expected, and the question is how small and auditable it can be. |
| **Forbidden** | The pattern can't be written at all, even with `unsafe`. Always a failure. |
| **Unsound** | Code the spec accepts as safe produces a data race, use-after-free, dangling view or other undefined behavior, with C and `unsafe` code that keep exactly what the spec asks of them ([08](08-c-interop/c-contract-and-embedding.md#what-c-must-uphold), [10](10-errors-and-safety/unsafe-code.md#unsafe-code)). It breaks a step of [13](13-soundness.md). **Always the most severe finding.** |

**Writing `copy` where the code makes a copy isn't ceremony**, since Rayo requires copies to be written out ([01](01-values-and-ownership/moves-copies-destruction.md#copies)). An extra copy that C++, C# or Swift wouldn't make is a cost.

**For each verdict, include the Rayo code you wrote (short) and the spec sections it relies on.** A case can't be marked Solved by pointing at a sentence in the spec: the code has to type-check under the rules as written.

Beyond the listed cases, the validator should hunt for **any other reasonable systems pattern the spec forbids or forces into `unsafe`**, and report it as a new case.

---

## Subchapters

- [Borrowed references and object graphs](hard-cases/borrowing-and-objects.md)
- [Concurrency and memory](hard-cases/concurrency-and-memory.md)
- [C interop, performance and hot reload](hard-cases/interop-performance-and-reload.md)
- [Reflection and systems patterns](hard-cases/reflection-and-systems.md)
- [Ergonomics and memory cleanup](hard-cases/ergonomics-and-cleanup.md)
