# Toolchain

`rayoc`, the reference compiler, is a Swift package at the root of this repository. Why Swift, LLVM and Linux CI is in [ADR 0001](docs/adr/0001-reference-compiler-in-swift-with-llvm.md).

```sh
swift build
swift test
swift run rayoc parse program.rayo
```

## The first phase: checking the rules

The first phase validates the static rules on a subset of the language before any backend exists. It builds:

1. **A checker** for the subset's rules: moves and partial moves, borrows and exclusivity, dependency sets ([02](docs/02-views-and-dependencies.md#dependencies), rules 1 to 5), `deinit`, and closures with their kinds, captures and `keep`.
2. **A reference interpreter** that runs checked programs over an explicit memory model, with allocations, initialization state and a tag per borrow, and stops at the first access that breaks an invariant of [15](docs/15-soundness.md). It is the checker's oracle: a program the checker accepts must never stop it.
3. **A program generator** that produces random programs in the subset, for the checker and the interpreter to cross-check.
4. **Compile tests** from the [hard cases](docs/hard-cases.md): each "Must accept" bullet in the subset is a program the checker must accept.

The subset is:

- `Int`, `Bool`, structs, inline arrays, and the library types `List`, `Box`, `Span` and `MutableSpan`;
- functions with borrowed, `mutable` and `owned` parameters;
- `let`, `var`, `owned`, `&`, `copy` and `consume`;
- `if`, `while` and `for i in a..<b`;
- closures.

Generics, optionals, accessors, `rebind`, objects, arenas, threads and C come after it.

## Layout

| Path | Holds |
| --- | --- |
| `Sources/RayoSyntax` | The lexer, the parser, the syntax tree and its text dump |
| `Sources/RayoDriver` | What each `rayoc` command does, given its arguments and a way to read files |
| `Sources/rayoc` | The executable: reads files and writes the driver's output and errors |
| `Tests/RayoSyntaxTests` | The lexer's and the parser's tests |
| `Tests/RayoDriverTests` | The commands' tests, over files held in memory |
