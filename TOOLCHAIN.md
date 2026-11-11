# Toolchain

The Rayo toolchain is a Swift package at the root of this repository. It builds two executables: `rayo`, the driver, and `rayoc`, the reference compiler.

- **SwiftPM only.** No Xcode project files, and no Apple-only frameworks: the compiler reaches the C library through `Glibc`, `Musl`, `Darwin` or `CRT`.
- **One package dependency, `swift-syntax`,** which the macros that build the table of diagnostic codes are written with.
- **CI tests on Linux, macOS and Windows**: on Linux in the `swift:6.4-noble` container, on macOS with the runner's Xcode that holds Swift 6.4, and on Windows x64 with Swift 6.4 and the build of LLVM that LLVM publishes for Windows. Code must pass on all three. A pull request runs only the test targets that its changes reach through the manifest's dependencies, and a push to `main` runs them all.
- **LLVM is the backend.** `rayoc` builds each program's module through LLVM's C API and has LLVM write the object code. It never writes LLVM IR as text, and the only such text it reads is the program runtime's.

## Build it

Install LLVM 23, as [LLVM](#llvm) says. Then build `rayo` and `rayoc`, and put the directory that holds them on your search path:

```sh
swift build -c release
export PATH="$(swift build -c release --show-bin-path):$PATH"
```

## Use it

`rayo` is the command you run. It checks a program, builds it into an executable beside it, or builds and runs it:

```sh
rayo check program.rayo
rayo build program.rayo
rayo run program.rayo
```

A file without a `main` function is a library. `rayo check` checks it as it checks a program, but `rayo build` and `rayo run` refuse it with E0201, since an executable starts at `main`.

## Test it

```sh
swift test
```

## How rayo and rayoc work together

`rayo check`, `rayo build` and `rayo run` have `rayoc` check or compile the program, in a process of its own, and `rayo build` and `rayo run` link the object code `rayoc` writes with the clang and LLD of the LLVM they were built against. `rayo` runs the `rayoc` beside it, or the one the `RAYOC` environment variable names.

`rayoc` takes one source file, and writes no file but its object code:

| Command line | Does |
| --- | --- |
| `rayoc --check [--] <file>` | Checks the file, a program or a library, and writes no file |
| `rayoc [--debug \| --release] -o <object file> [--] <file>` | Compiles the file, which must have a `main`, to object code for the host, in release mode where no mode is named, and writes it to the object file |

`--` ends the options, so the file after it may be named like one; `rayo` always passes it. `rayoc` exits with 0 when it checked or compiled the file, 1 when the program has errors or `rayoc` couldn't go on, and 2 when the arguments name no compile. It writes the program's errors, or why it stopped, to its standard error, and `rayo` passes on what it writes there as it is.

## LLVM

`rayoc` builds against one major release of LLVM, 23, and links its shared library. `rayo` links programs with that release's clang and LLD, and links no LLVM library itself. Install all three before you build:

| Platform | Install |
| --- | --- |
| macOS | `brew install llvm@23 lld@23` |
| Ubuntu or Debian | `llvm-23-dev clang-23 lld-23`, from [apt.llvm.org](https://apt.llvm.org) or the distribution |

`Package.swift` looks for LLVM 23 under `/usr/lib/llvm-23`, where apt installs it, and under `opt/llvm@23` and `opt/llvm` in Homebrew's prefix, `/opt/homebrew` or `/usr/local`. It takes the first of them whose `llvm/Config/llvm-config.h` names major version 23, and builds against its headers and libraries. Where LLVM 23 is installed anywhere else, set `LLVM_PREFIX` to the directory that holds its `include` and `lib`.

`rayo` runs the `clang` in that LLVM's `bin`. It looks for LLD 23 in that LLVM's prefix, then in `/usr/lib/llvm-23`, where apt installs it, and then in `opt/lld@23` and `opt/lld` in Homebrew's prefix. Where LLD 23 is installed anywhere else, set `LLD_PREFIX` to the directory that holds its `bin`. Both paths are fixed when `rayo` is built, so the clang and LLD on the search path don't matter. A missing clang or LLD is an error when a program is linked, not when `rayo` is built.

SwiftPM caches what `Package.swift` found, so it doesn't look again when the LLVM install changes. After installing, moving or upgrading LLVM, run `swift package purge-cache`, which clears that cache, and build again.

Homebrew's `libLLVM` names `opt/llvm` as the place it's loaded from, even when it was installed as `llvm@23`. So once `brew upgrade` takes Homebrew's `llvm` past release 23, a `rayoc` built against it stops loading. Install `llvm@23`, run `swift package purge-cache`, and build again. Where `Package.swift` finds only another release, it stops and says which.

On macOS the linker warns that `libLLVM` was built for a newer macOS than `rayoc` is. Homebrew builds its bottles per macOS release, and installs the one for the machine's own, so the warning is harmless on that machine.

The release lives in two places: `llvmMajorVersion` in `Package.swift`, and `LLVM_MAJOR_VERSION` in `.github/workflows/ci.yml`. A move to a new release changes both, with any changes the C API and the program runtime's LLVM IR need.

Optimisation follows the build mode: a debug build runs no LLVM passes and generates code at `-O0`, and a release build runs LLVM's `-O2` pipeline and generates code at `-O2`.

## Program runtime

The program runtime is the code every Rayo program links besides its own: the C entry point, and the functions a program calls to print and to report a panic. It will be written in Rayo, once `rayoc` can compile it. Until then it is LLVM IR written by hand, in the `.ll` files of `Sources/RayoRuntime`, in the syntax of the LLVM release `rayoc` builds against.

`rayoc` embeds those files in its own binary. For each program it parses them into the program's LLVM context, links them into the program's module, and then verifies and compiles the whole. So the runtime is part of every program's object code, and nothing is left to find when the program is linked or run.

Most of the runtime is the same everywhere. What it needs from the platform's C runtime is to ready a run and to write to standard error. That part is in `host-posix.ll` for macOS and Linux and in `host-windows.ll` for Windows, and `rayoc` links in the one for its platform.

## Linking

clang drives every link, so the platform's C startup files, C library and system library paths are the ones it would use for a C program. Which linker it runs is a choice of `rayo build` and `rayo run`:

| Option | Linker |
| --- | --- |
| `--linker=lld`, the default | LLD: `ld64.lld` for Mach-O on macOS, `ld.lld` for ELF on Linux, and `lld-link` for COFF on Windows |
| `--linker=platform` | The platform's own: the `ld` that `xcrun --find ld` names on macOS, or `/usr/bin/ld` where it names none; `/usr/bin/ld` on Linux; and on Windows the `link.exe` of the Visual Studio that clang links the C runtime from |

LLD is the default because it is the same linker, from the same LLVM, on every machine. The platform's linker is there for when a platform's own tools are required. Neither is taken from the search path.

## Layout

| Path | Holds |
| --- | --- |
| `Sources/RayoSource` | Positions and spans in a source file, which diagnostics, Rayo IR and panics point at |
| `Sources/RayoDiagnostics` | Diagnostics, and the `@Diagnostics` and `@Code` macros, which give each diagnostic code a number and a message |
| `Sources/RayoDiagnosticsMacros` | Those macros' implementation |
| `Sources/RayoSyntax` | The lexer, the parser and the syntax tree |
| `Sources/RayoSema` | The checker, which resolves names and checks types, giving a checked program, and the type table, which says how a value of each type lies in memory |
| `Sources/RayoIR` | Rayo IR, a checked program as a control-flow graph, and the lowering to it |
| `Sources/RayoOwnership` | The initialization checker, which follows what each local holds through Rayo IR's control flow, and reports the uses of locals that may hold no value, and the assignments to `let`s that may already have been assigned |
| `Sources/CLLVM` | The module map that imports LLVM's C API into Swift, and the directories of the clang and LLD that `Package.swift` found |
| `Sources/RayoRuntime` | The program runtime, as LLVM IR files that `rayoc` embeds |
| `Sources/RayoLLVM` | The compiler of Rayo IR to object code through LLVM, which links the program runtime into each program |
| `Sources/RayoCompiler` | What `rayoc` does, given its arguments and a way to read and write files: the pipeline that reads, checks and compiles a source file, and writes its object code |
| `Sources/rayoc` | The compiler's executable: reads and writes files, and writes the compiler's errors |
| `Sources/RayoLLVMInstall` | The LLVM install the toolchain was built against, whose clang and LLD link programs |
| `Sources/RayoDriver` | What each `rayo` command does, given its arguments and the `rayoc` to run: the `rayoc` it runs out of process, and the clang and linker it links a program with |
| `Sources/rayo` | The driver's executable: finds `rayoc` beside itself, and writes the driver's output and errors |
| `Tests/RayoDiagnosticsTests` | The messages and numbers the macros give a table of codes |
| `Tests/RayoDiagnosticsMacrosTests` | The errors the macros give a table written wrong |
| `Tests/RayoSyntaxTests` | The lexer's and the parser's tests |
| `Tests/RayoSemaTests` | The tests of the type table's layouts, and of which kind of declaration each top-level name belongs to, over parsed files |
| `Tests/RayoCompilerTests` | The tests of `rayoc`'s command line, of its pipeline's steps, and of the errors it reports for each program, over files held in memory |
| `Tests/RayoDriverTests` | The commands' tests, which run each command with the built `rayoc` on files in a temporary directory, and check its exit code, output and errors |
| `Tests/ToolStandIn` | What a stand-in for a tool `rayo` runs does in the driver tests, and how a test installs one: a few steps, such as writing to standard error, then an exit, a signal, or a hand-off to the real tool |
| `Tests/tool-stand-in` | The executable that acts as the stand-in installed at the path it was started as, in the driver tests |
| `Tests/TestSelection` | Which test targets a change reaches, through the manifest's dependencies |
| `Tests/select-tests` | The executable that CI runs to choose the tests a pull request needs |
| `Tests/TestSelectionTests` | The tests of the choice of test targets |
| `Tests/RayoIRTests` | The tests of the Rayo IR that lowering gives each construct, over programs the front end parses and checks |
| `Tests/RayoOwnershipTests` | The initialization checker's tests, over Rayo IR written by hand |
| `Tests/RayoLLVMTests` | The tests of the object code Rayo IR compiles to, read with the LLVM install's own tools; of the code each operator emits, run in the test process through LLVM's JIT; and of the LLVM types a program's values, functions and stack slots get |
| `Tests/CLLVMJIT` | The module map that imports LLVM's JIT into the LLVM tests, and into nothing that ships |
| `Tests/RayoLLVMTestSupport` | The C code that stands in for the runtime's panic in the LLVM tests, and ends the call that panicked instead of the process |
