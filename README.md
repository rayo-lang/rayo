# Rayo

Rayo is a general-purpose systems programming language. It gives the same control over memory, layout and performance as C++, and it adds memory safety: safe Rayo code can't read freed memory or race on data. It does this without a garbage collector, implicit reference counting or lifetime annotations.

Game development is one of Rayo's priorities: engines and gameplay code, of the kind written in C++ today and shipped on consoles.

> [!NOTE]
> **Rayo is in design.** The [language spec](#read-the-spec) is written and under review. The reference compiler, `rayoc`, parses a first subset of the language, but it can't check or run programs yet. This is a good time to question the design and to help build the compiler: see [Contribute](#contribute).

Source files use the `.rayo` extension.

## A first look

```swift
struct Enemy(var pos: Vec3, var hp: Float)
func heal(_ e: mutable Enemy) { e.hp = 100 }

var a = Enemy(pos: .zero, hp: 100)
var b = copy a                     // a copy, written out: Enemy is copyable, so this is a memcpy
b.hp = 50                          // changes only 'b'
heal(&a)                           // a borrow: heal changes 'a' in place, without copying it
let spot = borrow a.pos            // also a borrow: 'a.pos' can't change while 'spot' is in use

var names = List<String>()         // an empty list, which owns the buffer it allocates as it grows
names.append("grunt")
var backup = names.clone()         // a copy of heap data is a named call, and it allocates
var moved = names                  // a move: using 'names' after this is a compile error

var enemies = Pool<Enemy>()
let h = enemies.insert(b)          // 'b' moves in; h is a Handle<Enemy>, a small, copyable link to it
enemies.remove(h)
enemies[h]?.hp -= 10               // skipped: the element is gone, so enemies[h] is nil
```

## Key ideas

- **Every value has one owner.** Handing a value over moves it, and the place it came from can't be used until it gets a new value. A call borrows its arguments, unless a parameter is declared `owned`. Copies are written out: `copy x` for a copyable value, `x.clone()` for one that owns heap memory ([01](docs/spec/01-values-and-ownership.md)).
- **The compiler checks borrows inside each function.** Code that uses a value without owning it borrows it. While a value changes through one borrow, nothing else can touch it, and while a value is read, nothing can change it. No borrow escapes the function that makes it, so Rayo needs no lifetime annotations ([01](docs/spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). A view, such as a `Span` of a list's elements, can't outlive the scope that lent it ([02](docs/spec/02-views-and-dependencies/scoped-values.md#scoped-values)).
- **Links that live longer are checked at each use.** A link that must outlive a function, such as an enemy's target, is a `Handle<T>` into a `Pool<T>`, or a `WeakPointer<T>` to an object that a `UniquePointer<T>` owns. A link to something that is gone reads `nil`: it can go stale, but it never dangles. A link owns nothing, so cycles can't leak ([03](docs/spec/03-handles-and-objects.md)).
- **No data races.** The same borrow rules check work handed to other threads, and only `Sendable` values can reach another thread. The compiler derives `Sendable` from what a type holds ([07](docs/spec/07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)).
- **Allocators are values the code can name.** Every heap allocation goes through one, and every collection records which one. An arena releases everything at once when it is reset, and that stays safe: a collection that outlives the reset panics when code next reaches its contents, and never reads reused memory ([06](docs/spec/06-memory-and-allocators.md)).
- **Each check has a tier and a cost** ([01](docs/spec/01-values-and-ownership.md#tiers-of-checking)):
    - **static:** the compiler checks values, moves, borrows and scoped views, at no run-time cost;
    - **dynamic:** handles, weak pointers, `Slice`s, locks and a few others are checked at each use, at a small cost that their type or declaration shows;
    - **`unsafe`:** raw pointers and calls into C aren't checked, and the source marks them. A module declared `@safe` can't contain them ([10](docs/spec/10-errors-and-safety/unsafe-code.md#unsafe-code)).

  No build setting turns the memory-safety checks off. Bounds checks stay on in release builds ([10](docs/spec/10-errors-and-safety/checks-and-build-modes.md#check-levels)).
- **Rayo runs where C runs.** Every feature can be implemented in portable C. So a 64-bit platform whose only toolchain is its vendor's C compiler, such as a console, can run Rayo if it meets a few basic requirements ([11](docs/spec/11-compilation-model.md#what-a-target-must-provide), [08](docs/spec/08-c-interop/c-contract-and-embedding.md#what-the-runtime-needs-from-the-platform)). Rayo calls C and exports C directly. It has no C++ interop.

## Why Rayo

- **From C++,** Rayo keeps the control over memory and layout. Safe code has no use-after-free, no data races and no undefined behavior, and modules replace headers.
- **From Rust,** Rayo keeps memory safety without lifetime annotations. Borrows stay inside a function, and stored links, such as a node's parent or an observer, are handles and weak pointers. So any object graph, cycles included, is expressible in safe code.
- **From Swift,** Rayo keeps the syntax without ARC. It has no implicit reference counting and no copy-on-write, and generics are always specialized.
- **From C#,** Rayo keeps safety without a garbage collector. Memory is released at points you can see in the source, and nothing needs a JIT.

[Why Rayo](docs/why-rayo.md) makes the full case: the six design pillars, each problem Rayo answers in C++, Rust, Swift and C#, and a small game that uses most of the ideas.

## Learn Rayo

The [guide](docs/guide/) teaches Rayo in eight chapters, for programmers who know C++, Rust, Swift or C#. Each chapter starts from a problem that systems code has, solves it in Rayo, and links to the spec sections that hold the full rules.

## Read the spec

The spec has one chapter per topic, in [`docs/spec/`](docs/spec/), and the [glossary](GLOSSARY.md) says in a sentence what each of its terms means. To learn the memory model, start with 01 to 03, then read 06 and 07. [13](docs/spec/13-soundness.md) argues why safe code has no undefined behavior, and the [hard cases](docs/spec/hard-cases.md) are the systems patterns the spec is tested against.

| Doc | Covers |
| --- | --- |
| [01 Values and ownership](docs/spec/01-values-and-ownership.md) | Copy and move, parameters and bindings, borrows and `mutable`, the law of exclusivity |
| [02 Views and dependencies](docs/spec/02-views-and-dependencies.md) | Views and scoped values, how the compiler tracks what they borrow, `rebind`, and `read`, `modify`, `get` and `set` accessors |
| [03 Handles and objects](docs/spec/03-handles-and-objects.md) | Pools and handles, `UniquePointer` and `WeakPointer`, pinning for C |
| [04 Types](docs/spec/04-types.md) | Numbers, [SIMD](docs/spec/04-types/numbers-and-math.md#simd-and-math), structs, enums and [`when`](docs/spec/04-types/enums.md#matching-with-when-and-choosing-with-if), optionals, unions, strings, collections and iteration, `Pod`, `SoA` |
| [05 Protocols, generics and closures](docs/spec/05-protocols-generics-and-closures.md) | Protocols, generics, `any P`, operators, [equality and ordering](docs/spec/05-protocols-generics-and-closures/operators.md#equality-and-ordering), closures and function types, implicit conversions |
| [06 Memory and allocators](docs/spec/06-memory-and-allocators.md) | Allocator values and their contract, scoped default allocators, arena safety, `Box`, [`Shared` and `LocalShared`](docs/spec/06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners), [releasing values without destroying them](docs/spec/06-memory-and-allocators/allocation-lifecycle.md#releasing-a-value-without-destroying-it-trivialfree) |
| [07 Concurrency](docs/spec/07-concurrency.md) | Race freedom, [`Sendable`](docs/spec/07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable), [lending work to other threads](docs/spec/07-concurrency/thread-work.md#lending-work-to-other-threads), [threads](docs/spec/07-concurrency/thread-work.md#work-that-outlives-the-caller-threads), [locks and `Synchronized`](docs/spec/07-concurrency/synchronization.md#atomics-and-locks), [global state](docs/spec/07-concurrency/global-state.md#global-state), [stepped tasks](docs/spec/07-concurrency/tasks.md#semantics) |
| [08 C interop](docs/spec/08-c-interop.md) | `import c`, layout, pointers, callbacks, exports and generated headers, [embedding Rayo in a C program](docs/spec/08-c-interop/c-contract-and-embedding.md#the-platform-and-embedding-rayo-in-c) |
| [09 Compile time](docs/spec/09-compile-time.md) | `const`, `static if` and `static for`, reflection, attributes, conditional compilation, [generating declarations](docs/spec/09-compile-time/declaration-generation.md#generating-declarations) |
| [10 Errors and safety](docs/spec/10-errors-and-safety.md) | Typed `throws`, panics, [`unsafe` code and `@safe` modules](docs/spec/10-errors-and-safety/unsafe-code.md#unsafe-code), [check levels](docs/spec/10-errors-and-safety/checks-and-build-modes.md#check-levels), build modes |
| [11 Compilation model](docs/spec/11-compilation-model.md) | Modules and names, local type checking, no hidden costs in any build, [what a target must provide](docs/spec/11-compilation-model.md#what-a-target-must-provide), [what the language leaves open](docs/spec/11-compilation-model.md#what-the-language-leaves-open) |
| [12 Grammar](docs/spec/12-grammar.md) | EBNF grammar |
| [13 Soundness](docs/spec/13-soundness.md) | Why safe code has no undefined behavior: five invariants, and the rules that keep each |
| [Hard cases](docs/spec/hard-cases.md) | Systems patterns the spec is tested against |

## Repository layout

| Path | Holds |
| --- | --- |
| [`docs/guide/`](docs/guide/) | The guide, which teaches the language chapter by chapter |
| [`docs/spec/`](docs/spec/) | The spec and the hard cases |
| [`docs/`](docs/) | [Why Rayo](docs/why-rayo.md), and the [agent docs](docs/agents/) the project rules point to |
| [`GLOSSARY.md`](GLOSSARY.md) | The spec's terms, each with a one-sentence description and a link to its definition |
| [`examples/`](examples/) | [A gameplay module](examples/gameplay/gameplay.rayo), [a platform module](examples/platform/bindings.rayo) that binds a platform SDK's C header and runs the game from `main`, and [a job-parallel simulation](examples/jobs/jobs.rayo) on std's job system |
| `Sources/`, `Tests/` | `rayoc` and its tests. [TOOLCHAIN.md](TOOLCHAIN.md#layout) says what each module does |
| [`AGENTS.md`](AGENTS.md), [`.agents/skills/`](.agents/skills/) | The project rules, and the workflows that AI coding agents follow in this repository |

## Contribute

Rayo is early, so questions and criticism of the design help as much as code.

- **Ask questions and report problems** in [GitHub issues](https://github.com/rayo-lang/rayo/issues). A rule that is hard to follow, two parts of the spec that disagree, and a program the spec accepts that isn't safe are each worth an issue.
- **Find work** in the issues labeled [`good first issue`](https://github.com/rayo-lang/rayo/labels/good%20first%20issue), [`help wanted`](https://github.com/rayo-lang/rayo/labels/help%20wanted) or [`ready-for-human`](https://github.com/rayo-lang/rayo/labels/ready-for-human).
- **Propose a spec change in an issue first,** so it can be discussed before anyone writes it. A spec change is reviewed against the soundness argument in [13](docs/spec/13-soundness.md) and the criteria of the [hard cases](docs/spec/hard-cases.md).
- **Change the compiler** test first: write a test, see it fail for the right reason, then write the code that makes it pass. [TOOLCHAIN.md](TOOLCHAIN.md) says how to build and test `rayoc`, and the [issues](https://github.com/rayo-lang/rayo/issues) say what it builds next, each with the issues that block it. CI builds and tests on Linux with Swift 6.4, and a change must pass there. Comments and test names give the reason in place, and don't point at issues, pull requests or spec sections.
- **Work on a branch** named `impl-<feature-slug>`, never on `main`. A pull request description has two sections, **Purpose** (why the change exists) and **What changed** (the change at a high level), and ends with `Closes #N` for each issue it resolves.

[AGENTS.md](AGENTS.md) has the full project rules.

## License

Rayo is released under the [MIT License](LICENSE).
