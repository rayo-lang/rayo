# Compiler stages

`rayoc` compiles a file in stages, and each stage owns a kind of question about the program. A change goes in the stage that owns the question it decides, as the `code-style` skill says. `Package.swift` says which stage may use which, and [TOOLCHAIN.md](../../TOOLCHAIN.md#layout) what each module holds.

This page names each stage's kind of question, not each question. A new feature whose question fits a stage's kind leaves the page as it is; a change edits it only to add a stage or to move a kind of question from one stage to another.

| Stage | Modules | Owns |
|---|---|---|
| Source and diagnostics | `RayoSource`, `RayoDiagnostics`, `RayoDiagnosticsMacros` | Positions in the source text, and the errors the compiler can report. The stage that finds an error decides when and where it is reported. |
| Syntax | `RayoSyntax` | What the text says: its tokens and its syntax tree. It knows no names and no types. |
| Semantic checking | `RayoSema` | What the program means: what names refer to, the types of expressions, and what each expression does. It produces the checked program. |
| Lowering | `RayoIR` | How the checked program runs as control flow. It reports no errors. |
| Ownership | `RayoOwnership` | The rules about values over a function's paths. |
| Emitting | `RayoLLVM`, `RayoRuntime`, `LLVM`, `CLLVM` | How the program becomes LLVM code, and the runtime it links. It reports no errors in the program. |
| Pipeline | `RayoCompiler`, `rayoc` | Which stages run, in what order, and what `rayoc` reads, writes and prints. |

The driver, `rayo`, in `RayoDriver` and `RayoLLVMInstall`, runs `rayoc` and links what it writes: it lies outside `rayoc`'s stages.
