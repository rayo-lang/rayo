# Roadmap

Rayo's [spec](docs/spec/README.md) defines the whole language, and `rayoc` builds it a small version at a time. Each version adds a few features of the spec, end to end: a program that uses them parses, checks, compiles, links and runs. This file plans two versions ahead, and no further.

## How a version is done

**A version is done when every feature it lists runs end to end, and its proof program shows it.** The proof program is one Rayo program, `examples/v0.N/<name>.rayo`, with its expected output beside it in `<name>.out`. A driver test runs it, in debug and in release builds, on every platform CI tests: macOS arm64, Linux x64 and Windows x64. The driver tests check each feature in detail, so the proof program only puts the features to work together.

**A half version, such as v0.1.5, adds one small feature.** It has no proof program of its own: it extends the program of the version before it.

**A finished version is tagged**, as `v0.1.0`, with short release notes. A version ships no binaries, and is built from source as [TOOLCHAIN.md](TOOLCHAIN.md) says.

## v0.1: functions, integers and structs

The first version proves the language end to end with the smallest set of features a meaningful program needs. Its proof program is a combat simulation: enemies are structs that take hits in a loop until one of them falls, and the program prints their health as it goes.

These features already run:

- functions with labeled, borrowed parameters, results and recursion;
- `Int` and `Bool`, with integer literals and every arithmetic, comparison and logical operator;
- overflow, which panics in a debug build and wraps in a release build, and division by zero, which panics in both;
- `let` and `var` locals, assignment and compound assignment;
- `if`, `else`, `while`, `break` and `continue`;
- moves and `copy`, with the checks that a local is assigned before it is used;
- `print(Int)`.

These are still to do:

- **Structs.** A struct is made with its primary initializer, as `Enemy(hp: 100, armor: 5)`. A program reads a field, nested ones included, assigns a field of a `var` local, and copies a struct with `copy`. Moving a field out leaves the struct unusable until the field is assigned again ([01](docs/spec/01-values-and-ownership/moving-values-out.md)). Field defaults wait.
- **`print(Bool)`**, which prints `true` or `false`.
- **Bugs:** [#149](https://github.com/rayo-lang/rayo/issues/149), [#178](https://github.com/rayo-lang/rayo/issues/178), [#179](https://github.com/rayo-lang/rayo/issues/179), and on Windows [#220](https://github.com/rayo-lang/rayo/issues/220) and [#221](https://github.com/rayo-lang/rayo/issues/221).
- **Refactor:** [#177](https://github.com/rayo-lang/rayo/issues/177).

## v0.1.5: Float

`Float`, with its literals, arithmetic and comparisons, the conversions `Float(i)` and `Int(f)`, and `print(Float)`. The other number types, implicit widening, and the operators `&+` and `+|` wait.

## v0.2: inline arrays

An inline array, `[N of T]`, holds `N` values in place, with no heap ([04](docs/spec/04-types/collections.md#tuples-ranges-and-arrays)). A program makes one with a literal or with `.init(repeating:)`, reads and assigns an element as `a[i]`, and panics on an index out of bounds.

## v0.3: changing values in place

`mutable` and `owned` parameters, with the exclusivity rules that keep two accesses from overlapping ([01](docs/spec/01-values-and-ownership/exclusivity.md)), and `mutating func`, which takes `self` as a `mutable` parameter.

## Not yet planned

These come after v0.3, in an order not yet decided:

- `for` loops and ranges;
- C interop, and the raw pointers and `unsafe` code it needs;
- views such as `Span`, and the scoped values they are ([02](docs/spec/02-views-and-dependencies.md));
- heap storage: allocators, generics, and owning collections such as `List`;
- text;
- enums and optionals;
- the other number types;
- installing a toolchain ([#184](https://github.com/rayo-lang/rayo/issues/184), [#216](https://github.com/rayo-lang/rayo/issues/216));
- arm64 Windows ([#186](https://github.com/rayo-lang/rayo/issues/186)).

## Open design questions

**How many text types the language has.** The spec defines three: `StaticString` for immortal text, the scoped view `StringView`, and the owning `String` ([04](docs/spec/04-types/collections.md#collections-and-strings)). Most languages have one, and Rust's two are already a lot for a user to learn. This is settled in the spec before any text work starts.
