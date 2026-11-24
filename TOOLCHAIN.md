# Toolchain

The Rayo toolchain is a Swift package at the root of this repository. It builds two executables: `rayo`, the driver, and `rayoc`, the reference compiler.

- **SwiftPM only.** No Xcode project files, and no Apple-only frameworks: the compiler reaches the C library through `Glibc`, `Musl`, `Darwin` or `CRT`.
- **Swift 6.4, and macOS 27 or later**, whose standard library has the spans and the unique-ownership types the code-style rules call for. Linux and Windows need no particular release.
- **One package dependency, `swift-syntax`,** which the macros that build the table of diagnostic codes are written with.
- **CI tests on Linux, macOS and Windows**: on Linux in the `swift:6.4-noble` container, and on macOS with the runner's Xcode that holds Swift 6.4. On Windows it tests x64 and arm64, each built natively, with Swift 6.4 and the build of LLVM that LLVM publishes for it. Code must pass on all four. On Linux, CI also builds `rayo` and `rayoc` in release, as [Build it](#build-it) does, and runs each version's proof program with them, in debug and in release builds. A pull request runs only the test targets that its changes reach through the manifest's dependencies, and a push to `main` runs them all.
- **LLVM is the backend.** `rayoc` builds each program's module through LLVM's C API and has LLVM write the object code. It never writes LLVM IR as text, and the only such text it reads is the program runtime's.

## Build it

Install LLVM 23, as [LLVM](#llvm) says. Then build `rayo` and `rayoc`, and put the directory that holds them on your search path:

```sh
swift build -c release
export PATH="$(swift build -c release --show-bin-path):$PATH"
```

On Windows, in PowerShell:

```powershell
swift build -c release
$env:Path = "$(swift build -c release --show-bin-path);$env:Path"
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

A change often reaches only a few of the test targets, so a script can run just those. It finds what your branch changed since it left `origin/main`, along with what you haven't committed yet. It then runs each test target that depends on a changed module, directly or through others, as the package manifest says. A change to a file the tests read outside every module, such as the manifest, CI's workflow or a proof program, runs every test. A change no test reads only builds them. CI picks a pull request's tests the same way. Name another base with `--base`, and pass `swift test` its own arguments after `--`:

```sh
python3 scripts/run_affected_tests.py
python3 scripts/run_affected_tests.py --base impl-parser -- --parallel
```

Some tests compare what checking or lowering makes of a program with a snapshot: a file kept in a `Snapshots` directory beside the test, which holds the checked program or the Rayo IR as text. A test whose text differs fails with a diff. When a change means to change the text, run the tests with `RAYO_UPDATE_SNAPSHOTS=1` to rewrite the snapshots, and review their diff as part of the change:

```sh
RAYO_UPDATE_SNAPSHOTS=1 swift test
```

Only the directories that `scripts/check_imports.py` allows may import LLVM's C module, `CLLVM`, or the syntax tree's, `RayoSyntax`. It allows `RayoSyntax` to the checker, the pipeline and the tests that parse source, so nothing after semantic checking sees syntax. No file may re-export either. A target can import any module the build has made, even one it doesn't depend on, so the manifest can't enforce this. The script reads every Swift file's imports instead, and names each import that breaks a rule. CI runs it on every change to code, and you can run it from anywhere:

```sh
python3 scripts/check_imports.py
```

## Benchmark it

The test targets hold functional tests only. How fast `rayoc` is, and how its cost grows with a function's length, is measured from outside by `Benchmarks/benchmark.py`, which builds a release `rayoc` and runs it as a user does. Run it from anywhere:

```sh
python3 Benchmarks/benchmark.py
python3 Benchmarks/benchmark.py --filter check/
```

Each benchmark runs `rayoc` to one stop point over one program, and is named `stop/program-size`, such as `check/loops-800`. `check` runs `rayoc --check`, which runs every check and prints nothing. `emit-checked` and `emit-ir` print the checked program or the IR, and `compile-debug` and `compile-release` compile to object code. What a stop point does past checking costs the difference from `check`, which the script prints as each stage's cost.

- `loops-M` is a `main` of M copies of a block of two loops over an array of eight structs, each copy with names of its own: 16 M + 5 lines.
- `ref-let-loops-M` is a `main` of M copies of a block that borrows a `var` with a `ref let`, which stays in scope to the end, and loops three times reading it: 7 M + 2 lines.
- `straight-line-N` is a `main` of one block of N turns, each lending a `var` to a call and storing in it a value worked out from the result through a `let` of its own: 2 N + 6 lines.

M is 200, 400, 800 and 1600 unless `--sizes` names others, and N is five times M. `--stops` names the stop points to measure, such as `check,compile-debug`. The script measures the instructions `rayoc` retires and its peak memory, as the system reports them for the process, and its wall-clock time, and gives the median of three runs.

On Linux, `--counter valgrind` has Valgrind's Cachegrind count the instructions instead, with its cache and branch simulations off, on a processor it simulates, and takes peak memory and wall-clock time from a run of its own outside Valgrind.

The size of the environment and of the arguments, and Swift's random hash seed, each move that count by up to 0.14%. So the script runs a copy of `rayoc` from a temporary directory in `/tmp`, which is also its working directory, with only `SWIFT_DETERMINISTIC_HASHING=1` in its environment. Its count then varies by under 0.002%, from run to run and between builds from two checkouts, even on a virtual machine whose processor counts nothing, so it measures one run. Valgrind runs `rayoc` about 40 times slower, so measure small sizes with it:

```sh
python3 Benchmarks/benchmark.py --counter valgrind --sizes 50,100,200 --stops check,compile-debug
```

A baseline is a saved run to compare later runs with. The script names it for the commit it measured, and records what you say the code at that commit is, the machine and how it was measured:

```sh
python3 Benchmarks/benchmark.py --save --code 'main, as merged'
python3 Benchmarks/benchmark.py --compare 2042c3c1
```

A comparison fails where a benchmark's instructions rise more than 5% over the baseline's, since the system's count varies by up to 2.8% between runs, or more than 1% under Valgrind; `--threshold` names another. A baseline counted one way is never compared with a run counted the other. Peak memory and wall-clock time are reported, never compared, since peak memory varies by up to 11% between runs of one `rayoc` and wall-clock time with the machine's load.

CI's benchmark job compares each pull request that changes the compiler with its base, both measured in the same job on Linux with the command above. GitHub's runners are virtual machines whose processors count no instructions, so Valgrind counts them there. The job measures only checking and a debug compile: printing costs little past checking, and LLVM's optimisations make most of a release compile's cost.

## How rayo and rayoc work together

`rayo check`, `rayo build` and `rayo run` have `rayoc` check or compile the program, in a process of its own, and `rayo build` and `rayo run` link the object code `rayoc` writes with the clang and LLD of the LLVM they were built against. `rayo` runs the `rayoc` beside it, or the one the `RAYOC` environment variable names.

`rayoc` takes one source file, and writes no file but its object code. It prints to its standard output only what `--emit` asks for:

| Command line | Does |
| --- | --- |
| `rayoc --check [--] <file>` | Checks the file, a program or a library, and writes no file |
| `rayoc --emit=checked [--] <file>` | Checks the file, and prints its checked program as text |
| `rayoc --emit=ir [--] <file>` | Checks the file, and prints its Rayo IR as text, which reads back into the same IR |
| `rayoc [--debug \| --release] -o <object file> [--] <file>` | Compiles the file, which must have a `main`, to object code for the host, in release mode where no mode is named, and writes it to the object file |

`--` ends the options, so the file after it may be named like one; `rayo` always passes it. A program with only warnings compiles.

`rayoc` exits with 0 when it checked, printed or compiled the file, 1 when the program has errors or is a library given to `-o`, or `rayoc` couldn't go on, and 2 when the arguments name no compile. It writes the program's errors and warnings, each followed by a `note:` line for each place it labels, or why it stopped, to its standard error, and `rayo` passes on what it writes there as it is.

## LLVM

`rayoc` builds against one major release of LLVM, 23, and links its shared library. On Windows it links `LLVM-C`, which holds the C API, since MSVC can't build LLVM as one library. `rayo` links programs with that release's clang and LLD, and links no LLVM library itself. Install all three before you build:

| Platform | Install |
| --- | --- |
| macOS | `brew install llvm@23 lld@23` |
| Ubuntu or Debian | `llvm-23-dev clang-23 lld-23`, from [apt.llvm.org](https://apt.llvm.org) or the distribution |
| Windows x64 | The archive `clang+llvm-23.x.y-x86_64-pc-windows-msvc.tar.xz`, from [LLVM's releases](https://github.com/llvm/llvm-project/releases) |
| Windows arm64 | The archive `clang+llvm-23.x.y-aarch64-pc-windows-msvc.tar.xz`, from [LLVM's releases](https://github.com/llvm/llvm-project/releases) |

On Windows, install Swift 6.4 as [swift.org](https://www.swift.org/install/windows/) says, with the Visual Studio Build Tools and the Windows SDK it requires. clang links each program against Visual Studio's C runtime, and `--linker=platform` runs its `link.exe`. On arm64 Windows, install Swift's arm64 toolchain, and keep the component `Microsoft.VisualStudio.Component.VC.Tools.ARM64` that swift.org's Visual Studio command adds: it holds the C runtime and the `link.exe` that clang links arm64 programs with.

LLVM's installer for Windows holds no headers, so only the archive will do. It holds one directory, named as the archive is, with `include`, `lib` and `bin` in it. Windows' own `tar` takes many minutes over it, and 7-Zip is much faster, decompressing the archive in one pass and unpacking it in a second. The 7-Zip installer doesn't put it on the search path, so the commands run it from where it installs. Install 7-Zip, unpack the archive in a directory with a few gigabytes free, and move its directory to where LLVM is to stay, such as `C:\llvm`. These unpack the x64 archive; on arm64 Windows, name `aarch64` where they name `x86_64`:

```powershell
winget install 7zip.7zip
$sevenZip = "$env:ProgramFiles\7-Zip\7z.exe"
& $sevenZip x clang+llvm-23.x.y-x86_64-pc-windows-msvc.tar.xz
& $sevenZip x clang+llvm-23.x.y-x86_64-pc-windows-msvc.tar -oC:\
Remove-Item clang+llvm-23.x.y-x86_64-pc-windows-msvc.tar
Move-Item C:\clang+llvm-23.x.y-x86_64-pc-windows-msvc C:\llvm
```

`Package.swift` looks for LLVM nowhere on Windows, so set `LLVM_PREFIX` to that directory, and put its `bin` on the search path, where `rayoc` loads `LLVM-C.dll` from. These set them for the shell you are in:

```powershell
$env:LLVM_PREFIX = "C:\llvm"
$env:Path = "$env:LLVM_PREFIX\bin;$env:Path"
```

And these set them for every shell you open after. `$env:Path` holds the machine's search path as well as your own, so they add to your own alone, which keeps the machine's out of it:

```powershell
[Environment]::SetEnvironmentVariable("LLVM_PREFIX", "C:\llvm", "User")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "C:\llvm\bin;$userPath", "User")
```

A new shell's search path puts the machine's ahead of your own. So where the machine's holds another LLVM's `bin`, such as the `C:\Program Files\LLVM\bin` that LLVM's installer can add, `rayoc` loads that LLVM's `LLVM-C.dll`, and fails to start or crashes. Remove that LLVM from the machine's search path, or put `C:\llvm\bin` at its front, from a shell run as administrator:

```powershell
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
[Environment]::SetEnvironmentVariable("Path", "C:\llvm\bin;$machinePath", "Machine")
```

These commands, like the ones for your own search path, write it back with each `%VARIABLE%` in it replaced by the variable's value today. Where the search path holds an entry you want to keep following its variable, edit it in the Environment Variables dialog of System Properties instead.

On macOS and Linux, `Package.swift` looks for LLVM 23 where apt and Homebrew install it: under `/usr/lib/llvm-23`, and under `opt/llvm@23` and `opt/llvm` in Homebrew's prefix, `/opt/homebrew` or `/usr/local`. It takes the first of them whose `llvm/Config/llvm-config.h` names major version 23, and builds against its headers and libraries. Where LLVM 23 is installed anywhere else, set `LLVM_PREFIX` to the directory that holds its `include` and `lib`.

`rayo` runs the `clang` in that LLVM's `bin`. It looks for LLD 23 in that LLVM's prefix, then in `/usr/lib/llvm-23`, where apt installs it, and then in `opt/lld@23` and `opt/lld` in Homebrew's prefix. On Windows it looks only in LLVM's prefix, whose archive holds LLD. Where LLD 23 is installed anywhere else, set `LLD_PREFIX` to the directory that holds its `bin`. Both paths are fixed when `rayo` is built, so the clang and LLD on the search path don't matter. A missing clang or LLD is an error when a program is linked, not when `rayo` is built.

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

Each row says what a module or test target holds, and changes only when one is added, removed or given another role.

| Path | Holds |
| --- | --- |
| `Sources/RayoSource` | Positions and spans in a source file |
| `Sources/RayoDiagnostics` | Diagnostics, and the macros that build the table of diagnostic codes |
| `Sources/RayoDiagnosticsMacros` | Those macros' implementation |
| `Sources/RayoSyntax` | The parsing of source text into a syntax tree |
| `Sources/RayoCheckedProgram` | The checked program, which semantic checking gives and every later stage reads |
| `Sources/RayoSema` | The semantic checking of a syntax tree, which gives the checked program |
| `Sources/RayoIR` | Rayo IR, and the lowering of a checked program to it |
| `Sources/RayoOwnership` | The ownership checks over Rayo IR |
| `Sources/CLLVM` | The module map that imports LLVM's C API into Swift |
| `Sources/LLVM` | The Swift binding of LLVM's C API |
| `Sources/RayoRuntime` | The program runtime, as LLVM IR files that `rayoc` embeds |
| `Sources/RayoLLVM` | The compiling of Rayo IR to object code through LLVM |
| `Sources/RayoCompiler` | What `rayoc` does: the pipeline from a source file to what it writes or prints |
| `Sources/rayoc` | The compiler's executable |
| `Sources/CLLVMInstall` | The LLVM install that `Package.swift` found, as C constants |
| `Sources/RayoLLVMInstall` | That install, as Swift, whose clang and LLD link programs |
| `Sources/RayoDriver` | What each `rayo` command does |
| `Sources/rayo` | The driver's executable |
| `Tests/RayoSourceTests` | Tests of source positions |
| `Tests/RayoDiagnosticsTests` | Tests of diagnostics and the table of codes the macros build |
| `Tests/RayoDiagnosticsMacrosTests` | Tests of the macros' implementation |
| `Tests/RayoSyntaxTests` | Tests of parsing |
| `Tests/RayoSemaTests` | Tests of semantic checking |
| `Tests/RayoCompilerTests` | Tests of `rayoc`'s command line and pipeline, and of the errors of source programs that more than one stage takes part in |
| `Tests/RayoDriverTests` | Tests of the `rayo` commands, and of what whole programs print and how they end when built and run |
| `Tests/ToolStandIn` | Stand-ins for the tools `rayo` runs, for the driver tests |
| `Tests/tool-stand-in` | The executable a stand-in runs as |
| `Tests/LLVMTests` | Tests of the LLVM binding |
| `Tests/RayoIRTests` | Tests of Rayo IR and lowering |
| `Tests/RayoOwnershipTests` | Tests of the ownership checks |
| `Tests/RayoLLVMTests` | Tests of the code Rayo IR compiles to |
| `Tests/SnapshotTesting` | Snapshot testing for other test targets: comparing a test's text with a file kept beside it |
| `Tests/RayoLLVMTestSupport` | C stand-ins for the runtime's functions in the LLVM tests |

### Where a test goes

More than one test target could hold many tests: a test of what a loop prints could give the emitter IR, or give `rayo run` source. A test goes at the lowest level that can see what it checks. There it runs no more of the toolchain than what it checks needs, so it is quick, and a failure points at the code that is wrong.

Each kind of test has its target, and each target gives its tests the same kind of input:

- **What one stage makes of its input** goes in that stage's target, which calls the stage's own interface.
    - `RayoSyntaxTests` gives the lexer and the parser source text, and reads the tokens, the syntax tree and the syntax errors.
    - `RayoSemaTests` gives parsing and checking source text, and reads the errors and warnings. It compares the checked program of a source that checks with a snapshot.
    - `RayoIRTests` gives lowering source text that checks, and compares the IR with a snapshot. It gives the IR's verifiers, and the analyses that later stages build on, IR text.
    - `RayoOwnershipTests` gives the ownership checks IR text. It reads the errors they report, and the IR they give with each access and local ended.
    - `RayoLLVMTests` gives the emitter IR text, and reads the LLVM module and the object code it makes.
- **What emitted code does when it runs** goes in `RayoLLVMTests` too. A test gives the emitter IR text and runs the code in the test's own process. It reads what the code printed and the panic that ended it, in a debug and in a release build where the two could differ.
- **An error that more than one stage takes part in** goes in `RayoCompilerTests`, which gives source text to `rayoc --check` in the test's own process and reads the errors. An ownership error of a source program is one, since the program is parsed, checked and lowered before the ownership checks see it. How one stage's error bears on what the others report is another.
- **What a program prints, and how it ends, when built and run** goes in `RayoDriverTests`. A test gives source text to `rayo run`, which compiles it with the built `rayoc` and links it with the installed clang and LLD. It reads the program's output, its exit code and its panic, in a debug and in a release build where the two could differ.
- **What `rayo` and `rayoc` themselves do** goes in the target of each. `RayoCompilerTests` holds `rayoc`'s options, its exit codes, what it prints and the files it writes, and gives the compiler the files it reads. `RayoDriverTests` holds the same for `rayo`, and puts a stand-in in place of `rayoc`, clang or a linker where a test decides what that tool does.
