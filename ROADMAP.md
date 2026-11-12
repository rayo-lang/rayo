# Roadmap

Rayo's [spec](docs/spec/README.md) defines the whole language, and `rayoc` builds it a small version at a time. Each version adds a few features of the spec, end to end: a program that uses them parses, checks, compiles, links and runs. This file plans two versions ahead, and no further.

## How a version is done

**A version is done when every feature it lists runs end to end, and its proof program shows it.** The proof program is one Rayo program, `examples/v0.N/<name>.rayo`, with its expected output beside it in `<name>.out`. A driver test runs it, in debug and in release builds, on every platform CI tests: macOS arm64, Linux x64 and Windows x64. The driver tests check each feature in detail, so the proof program only puts the features to work together. The other programs in `examples/` show the whole language, which `rayoc` cannot compile yet, and no test runs them.

**Each version lists the features still to do, and the ones that already run.** The pull request that finishes a feature moves it from the first list to the second, and starts the second, headed as v0.1's is, when the version has none yet.

**A half version, such as v0.1.5, adds one small feature.** It has no proof program of its own: it extends the program of the version before it.

**A finished version is tagged**, as `v0.1.0`, with short release notes. A version ships no binaries, and is built from source as [TOOLCHAIN.md](TOOLCHAIN.md) says.

## v0.1: functions, integers and structs

The first version proves the language end to end with the smallest set of features a meaningful program needs. Its proof program is a combat simulation: enemies are structs that take hits in a loop until one of them falls, and the program prints their health as it goes.

These are still to do:

- **Fields.** A program assigns a field of a `var` local. Moving a field out leaves the struct unusable until the field is assigned again ([01](docs/spec/01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)).
- **Issues.**
  - [#178](https://github.com/rayo-lang/rayo/issues/178) and [#179](https://github.com/rayo-lang/rayo/issues/179) in the compiler;
  - [#220](https://github.com/rayo-lang/rayo/issues/220) and [#221](https://github.com/rayo-lang/rayo/issues/221) on Windows;
  - the refactor [#177](https://github.com/rayo-lang/rayo/issues/177).

These features already run:

- functions with labeled, borrowed parameters, results and recursion;
- `Int` and `Bool`, with integer literals, the arithmetic operators `+`, `-`, `*`, `/` and `%`, unary `-`, the comparisons, and `&&`, `||` and `!`;
- overflow, which panics in a debug build and wraps in a release build, and division by zero, which panics in both;
- `let` and `var` locals, assignment and compound assignment;
- `if`, `else`, `while`, `break` and `continue`;
- moves and `copy`, with the checks that a local is assigned before it is used;
- struct declarations, whose names are the types of locals, parameters and results, and `copy` of a struct;
- making a struct with its primary initializer, as `Enemy(hp: 100, armor: 5)`, which takes its arguments owned, and reading a field of a struct where a borrow of the field suffices, as `e.hp - 5` or `print(e.hp)`;
- a field of a struct type, given by a nested initializer call or by a local, which the call moves, and read through the struct that holds it, as `e.stats.hp`;
- `print(Int)`, and `print(Bool)`, which prints `true` or `false`.

## v0.1.5: Float

These are still to do:

- `Float`, with its literals, arithmetic and comparisons;
- the conversions `Float(i)` and `Int(f)`;
- `print(Float)`.

## v0.2: inline arrays

An inline array, `[N of T]`, holds `N` values in place, with no heap ([04](docs/spec/04-types/collections.md#tuples-ranges-and-arrays)).

These are still to do:

- making an inline array with a literal or with `.init(repeating:)`;
- reading and assigning an element, as `a[i]`;
- a panic on an index out of bounds.

## v0.3: changing values in place

These are still to do:

- `mutable` and `owned` parameters, with the [law of exclusivity](docs/spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity), and the error for an `owned` parameter that no code reads ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#unused-values));
- `mutating func`, which takes `self` as a `mutable` parameter.

## Not yet planned

These come after v0.3, in an order not yet decided:

- `for` loops and ranges;
- C interop, and the raw pointers and `unsafe` code it needs;
- views such as `Span`, which are [scoped values](docs/spec/02-views-and-dependencies/scoped-values.md);
- heap storage: allocators, generics, and owning collections such as `List`;
- text;
- field defaults;
- enums and optionals;
- the other number types, and implicit widening between them;
- the wrapping, saturating, bitwise and shift operators;
- installing a toolchain ([#184](https://github.com/rayo-lang/rayo/issues/184), [#216](https://github.com/rayo-lang/rayo/issues/216));
- arm64 Windows ([#186](https://github.com/rayo-lang/rayo/issues/186)).
