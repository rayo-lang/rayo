# Toolchain

`rayoc`, the reference compiler, is a Swift package at the root of this repository.

```sh
swift build
swift test
swift run rayoc parse program.rayo
```

- **SwiftPM only.** No Xcode project files, and no Apple-only frameworks: the compiler reaches the C library through `Glibc`, `Musl` or `Darwin`.
- **CI runs on Linux**, in the `swift:6.4-noble` container, and code must pass there whatever it does on macOS.
- **LLVM is the default backend, and C an alternative target** for platforms whose only toolchain is a vendor's C compiler, such as consoles ([12](docs/12-compilation-model.md#what-a-target-must-provide)). The C backend is supported and tested, but never the main path.

## Layout

| Path | Holds |
| --- | --- |
| `Sources/RayoSyntax` | The lexer, the parser, the syntax tree and its text dump |
| `Sources/RayoDriver` | What each `rayoc` command does, given its arguments and a way to read files |
| `Sources/rayoc` | The executable: reads files and writes the driver's output and errors |
| `Tests/RayoSyntaxTests` | The lexer's and the parser's tests |
| `Tests/RayoDriverTests` | The commands' tests, over files held in memory |
