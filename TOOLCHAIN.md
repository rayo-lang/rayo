# Toolchain

`rayoc`, the reference compiler, is a Swift package at the root of this repository.

```sh
swift build
swift test
swift run rayoc run program.rayo
```

`rayoc build` and `rayoc run` link with the `clang` on the search path.

- **SwiftPM only.** No Xcode project files, and no Apple-only frameworks: the compiler reaches the C library through `Glibc`, `Musl` or `Darwin`.
- **CI runs on Linux**, in the `swift:6.4-noble` container, and code must pass there whatever it does on macOS.
- **LLVM is the default backend, and C an alternative target** for platforms whose only toolchain is a vendor's C compiler, such as consoles ([11](docs/spec/11-compilation-model.md#what-a-target-must-provide)). The C backend is supported and tested, but never the main path.

## Layout

| Path | Holds |
| --- | --- |
| `Sources/RayoSyntax` | The lexer, the parser, the syntax tree and its text dump |
| `Sources/RayoSema` | The checker, which resolves names and checks types, giving a checked program |
| `Sources/RayoIR` | Rayo IR, a checked program as a control-flow graph, and the lowering to it |
| `Sources/RayoLLVM` | The writer of Rayo IR as textual LLVM IR, with the runtime that reports panics |
| `Sources/RayoDriver` | What each `rayoc` command does, given its arguments and a way to read files, and the `clang` it links with |
| `Sources/rayoc` | The executable: reads files and writes the driver's output and errors |
| `Tests/RayoSyntaxTests` | The lexer's and the parser's tests |
| `Tests/RayoDriverTests` | The commands' tests, over files held in memory |
