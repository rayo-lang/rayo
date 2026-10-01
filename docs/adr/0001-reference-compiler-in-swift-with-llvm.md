# 0001. The reference compiler is written in Swift, generates LLVM IR, and is tested on Linux

**`rayoc` is a Swift package built with SwiftPM. It generates LLVM IR by default, has a C backend as an alternative target, and its CI runs on Linux.**

**Problem.** The design's static rules need an executable check, and the language needs a compiler. Both need an implementation language, a way to generate code, and a platform that CI holds them to.

**Decision.**

- **Swift, with SwiftPM only.** No Xcode project files, and no Apple-only frameworks: the compiler reaches the C library through `Glibc`, `Musl` or `Darwin`, and avoids Foundation.
- **LLVM IR is the default backend.** A C backend is an alternative target for platforms whose only toolchain is a vendor's C compiler, such as consoles ([D4](../14-decisions.md#d4-every-feature-can-be-implemented-in-portable-c)). It is supported and tested, as WebAssembly is in rustc, but it is never the main path.
- **CI runs on Linux**, in the `swift:6.4-noble` container. Code must build and pass its tests there, whatever it does on macOS.
- **The rules come first.** The first phase is a checker and a reference interpreter for a subset of the language, which cross-check each other, before any backend.

**Why.** Swift reads close to Rayo, so the checker reads like the rules it implements, and its tests build and run in seconds. LLVM gives optimization, debug info and the desktop and mobile targets without a second compiler in every build. Holding CI to Linux keeps the compiler off macOS-only APIs. The static rules are where the design is most likely to be wrong, so a checker with an interpreter as its oracle tests them before any code generator depends on them.

**Cost.** Swift on Linux trails Swift on macOS in tooling, and Windows isn't covered by CI. Two backends must agree on every program, except where the language leaves the result open ([12](../12-compilation-model.md#what-the-language-leaves-open)). The compiler isn't written in Rayo.

**Rejected.**

- **Rust:** harder to read for this code, and its integration tests were slow to build and run.
- **C as the default backend:** every build would pass through a second compiler, which slows edit-build-run cycles, and debug info would describe the generated C rather than the Rayo source. It stays as the console path that D4 requires.
- **A full compiler before the rules are checked:** a backend built on rules that later change is rework.

This keeps D4: the language still has no feature that portable C can't implement, and the C backend is what demonstrates it. How a toolchain generates code is its own design ([D12](../14-decisions.md#d12-the-spec-defines-the-language-its-runtime-guarantees-and-library-contracts-not-libraries-or-tools)).
