# Toolchain

`rayoc`, the reference compiler, is a Swift package at the root of this repository.

```sh
swift build
swift test
swift run rayoc run program.rayo
```

`rayoc build` and `rayoc run` compile a program to object code themselves, and link it with the `clang` on the search path.

- **SwiftPM only.** No Xcode project files, and no Apple-only frameworks: the compiler reaches the C library through `Glibc`, `Musl` or `Darwin`.
- **One package dependency, `swift-syntax`,** which the macros that build the table of diagnostic codes are written with.
- **CI runs on Linux**, in the `swift:6.4-noble` container, and code must pass there whatever it does on macOS.
- **LLVM is the backend.** `rayoc` builds each program's module through LLVM's C API and has LLVM write the object code. It never writes LLVM IR as text, and the only such text it reads is the program runtime's.

## LLVM

`rayoc` builds against one major release of LLVM, 23, and links its shared library. Install it before you build:

| Platform | Install |
| --- | --- |
| macOS | `brew install llvm@23` |
| Ubuntu or Debian | `llvm-23-dev`, from [apt.llvm.org](https://apt.llvm.org) or the distribution |

`Package.swift` looks for LLVM 23 under `/usr/lib/llvm-23`, where apt installs it, and under `opt/llvm@23` and `opt/llvm` in Homebrew's prefix, `/opt/homebrew` or `/usr/local`. It takes the first of them whose `llvm/Config/llvm-config.h` names major version 23, and builds against its headers and libraries. Where LLVM 23 is installed anywhere else, set `LLVM_PREFIX` to the directory that holds its `include` and `lib`.

The release lives in two places: `llvmMajorVersion` in `Package.swift`, and `LLVM_MAJOR_VERSION` in `.github/workflows/ci.yml`. A move to a new release changes both, with any changes the C API and the program runtime's LLVM IR need.

Optimisation follows the build mode: a debug build runs no LLVM passes and generates code at `-O0`, and a release build runs LLVM's `-O2` pipeline and generates code at `-O2`.

## Program runtime

The program runtime is the code every Rayo program links besides its own: the C entry point, and the functions a program calls to print and to report a panic. It will be written in Rayo, once `rayoc` can compile it. Until then it is LLVM IR written by hand, in the `.ll` files of `Sources/RayoRuntime`, in the syntax of the LLVM release `rayoc` builds against.

`rayoc` embeds those files in its own binary. For each program it parses them into the program's LLVM context, links them into the program's module, and then verifies and compiles the whole. So the runtime is part of every program's object code, and nothing is left to find when the program is linked or run.

## Layout

| Path | Holds |
| --- | --- |
| `Sources/RayoSource` | Positions and spans in a source file, which diagnostics, Rayo IR and panics point at |
| `Sources/RayoDiagnostics` | Diagnostics, and the `@Diagnostics` and `@Code` macros, which give each diagnostic code a number and a message |
| `Sources/RayoDiagnosticsMacros` | Those macros' implementation |
| `Sources/RayoSyntax` | The lexer, the parser and the syntax tree |
| `Sources/RayoSema` | The checker, which resolves names and checks types, giving a checked program |
| `Sources/RayoIR` | Rayo IR, a checked program as a control-flow graph, and the lowering to it |
| `Sources/CLLVM` | The module map that imports LLVM's C API into Swift |
| `Sources/RayoRuntime` | The program runtime, as LLVM IR files that `rayoc` embeds |
| `Sources/RayoLLVM` | The compiler of Rayo IR to object code through LLVM, which links the program runtime into each program |
| `Sources/RayoDriver` | What each `rayoc` command does, given its arguments and a way to read files, and the `clang` it links with |
| `Sources/rayoc` | The executable: reads files and writes the driver's output and errors |
| `Tests/RayoDiagnosticsTests` | The messages and numbers the macros give a table of codes |
| `Tests/RayoDiagnosticsMacrosTests` | The errors the macros give a table written wrong |
| `Tests/RayoSyntaxTests` | The lexer's and the parser's tests |
| `Tests/RayoDriverTests` | The commands' tests, over files held in memory |
