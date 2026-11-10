# Toolchain

`rayoc`, the reference compiler, is a Swift package at the root of this repository.

```sh
swift build
swift test
swift run rayoc run program.rayo
```

`rayoc build` and `rayoc run` compile a program to object code themselves, and link it with the clang and LLD of the LLVM they were built against.

- **SwiftPM only.** No Xcode project files, and no Apple-only frameworks: the compiler reaches the C library through `Glibc`, `Musl` or `Darwin`.
- **macOS 27 or later**, whose standard library has the spans and the unique-ownership types the code-style rules call for. Linux needs no particular release.
- **One package dependency, `swift-syntax`,** which the macros that build the table of diagnostic codes are written with.
- **CI tests on Linux and macOS**: on Linux in the `swift:6.4-noble` container, on macOS with the runner's Xcode that holds Swift 6.4. Code must pass on both.
- **LLVM is the backend.** `rayoc` builds each program's module through LLVM's C API and has LLVM write the object code. It never writes LLVM IR as text, and the only such text it reads is the program runtime's.

## LLVM

`rayoc` builds against one major release of LLVM, 23, and links its shared library. It links programs with that release's clang and LLD. Install all three before you build:

| Platform | Install |
| --- | --- |
| macOS | `brew install llvm@23 lld@23` |
| Ubuntu or Debian | `llvm-23-dev clang-23 lld-23`, from [apt.llvm.org](https://apt.llvm.org) or the distribution |

`Package.swift` looks for LLVM 23 under `/usr/lib/llvm-23`, where apt installs it, and under `opt/llvm@23` and `opt/llvm` in Homebrew's prefix, `/opt/homebrew` or `/usr/local`. It takes the first of them whose `llvm/Config/llvm-config.h` names major version 23, and builds against its headers and libraries. Where LLVM 23 is installed anywhere else, set `LLVM_PREFIX` to the directory that holds its `include` and `lib`.

`rayoc` runs the `clang` in that LLVM's `bin`. It looks for LLD 23 in that LLVM's prefix, then in `/usr/lib/llvm-23`, where apt installs it, and then in `opt/lld@23` and `opt/lld` in Homebrew's prefix. Where LLD 23 is installed anywhere else, set `LLD_PREFIX` to the directory that holds its `bin`. Both paths are fixed when `rayoc` is built, so the clang and LLD on the search path don't matter. A missing clang or LLD is an error when a program is linked, not when `rayoc` is built.

SwiftPM caches what `Package.swift` found, so it doesn't look again when the LLVM install changes. After installing, moving or upgrading LLVM, run `swift package purge-cache`, which clears that cache, and build again.

Homebrew's `libLLVM` names `opt/llvm` as the place it's loaded from, even when it was installed as `llvm@23`. So once `brew upgrade` takes Homebrew's `llvm` past release 23, a `rayoc` built against it stops loading. Install `llvm@23`, run `swift package purge-cache`, and build again. Where `Package.swift` finds only another release, it stops and says which.

On macOS the linker warns that `libLLVM` was built for a newer macOS than `rayoc` is. Homebrew builds its bottles per macOS release, and installs the one for the machine's own, so the warning is harmless on that machine.

The release lives in two places: `llvmMajorVersion` in `Package.swift`, and `LLVM_MAJOR_VERSION` in `.github/workflows/ci.yml`. A move to a new release changes both, with any changes the C API and the program runtime's LLVM IR need.

Optimisation follows the build mode: a debug build runs no LLVM passes and generates code at `-O0`, and a release build runs LLVM's `-O2` pipeline and generates code at `-O2`.

## Program runtime

The program runtime is the code every Rayo program links besides its own: the C entry point, and the functions a program calls to print and to report a panic. It will be written in Rayo, once `rayoc` can compile it. Until then it is LLVM IR written by hand, in the `.ll` files of `Sources/RayoRuntime`, in the syntax of the LLVM release `rayoc` builds against.

`rayoc` embeds those files in its own binary. For each program it parses them into the program's LLVM context, links them into the program's module, and then verifies and compiles the whole. So the runtime is part of every program's object code, and nothing is left to find when the program is linked or run.

## Linking

clang drives every link, so the platform's C startup files, C library and system library paths are the ones it would use for a C program. Which linker it runs is a choice of `rayoc build` and `rayoc run`:

| Option | Linker |
| --- | --- |
| `--linker=lld`, the default | LLD: `ld64.lld` for Mach-O on macOS, `ld.lld` for ELF on Linux |
| `--linker=platform` | The platform's own: the `ld` that `xcrun --find ld` names on macOS, or `/usr/bin/ld` where it names none, and `/usr/bin/ld` on Linux |

LLD is the default because it is the same linker, from the same LLVM, on every machine. The platform's linker is there for when a platform's own tools are required. Neither is taken from the search path.

## Layout

| Path | Holds |
| --- | --- |
| `Sources/RayoSource` | Positions and spans in a source file, which diagnostics, Rayo IR and panics point at |
| `Sources/RayoDiagnostics` | Diagnostics, and the `@Diagnostics` and `@Code` macros, which give each diagnostic code a number and a message |
| `Sources/RayoDiagnosticsMacros` | Those macros' implementation |
| `Sources/RayoSyntax` | The lexer, the parser and the syntax tree |
| `Sources/RayoSema` | The checker, which resolves names and checks types, giving a checked program |
| `Sources/RayoIR` | Rayo IR, a checked program as a control-flow graph, and the lowering to it |
| `Sources/RayoOwnership` | The initialization checker, which follows what each local holds through Rayo IR's control flow, and reports the uses of locals that may hold no value, and the assignments to `let`s that may already have been assigned |
| `Sources/CLLVM` | The module map that imports LLVM's C API into Swift, and the directories of the clang and LLD that `Package.swift` found |
| `Sources/RayoRuntime` | The program runtime, as LLVM IR files that `rayoc` embeds |
| `Sources/RayoLLVM` | The compiler of Rayo IR to object code through LLVM, which links the program runtime into each program |
| `Sources/RayoDriver` | What each `rayoc` command does, given its arguments and a way to read files, and the clang and linker it links a program with |
| `Sources/rayoc` | The executable: reads files and writes the driver's output and errors |
| `Tests/RayoDiagnosticsTests` | The messages and numbers the macros give a table of codes |
| `Tests/RayoDiagnosticsMacrosTests` | The errors the macros give a table written wrong |
| `Tests/RayoSyntaxTests` | The lexer's and the parser's tests |
| `Tests/RayoDriverTests` | The commands' tests, over files held in memory |
| `Tests/RayoOwnershipTests` | The initialization checker's tests, over Rayo IR written by hand |
| `Tests/RayoLLVMTests` | The tests of the object code Rayo IR compiles to, read with the LLVM install's own tools |
