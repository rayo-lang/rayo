# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

All five labels exist on `rayo-lang/rayo`. If one is ever missing, create it with `gh label create -R rayo-lang/rayo "<name>"` before applying it.

Edit the right-hand column to match whatever vocabulary you actually use.

## Area labels

**Every triaged issue carries one or two `area:` labels**: the area that owns the question the issue decides, and, only when much of its work lands in another area, the one other area it changes most. An epic takes none, since its sub-issues carry theirs. The compiler's areas are named for its stages in [compiler-stages.md](compiler-stages.md), which says what each stage owns. A path the table doesn't list takes the area of the work it serves, as a test target takes its stage's.

| Label | Covers |
| --- | --- |
| `area:diagnostics` | `RayoSource`, `RayoDiagnostics`, `RayoDiagnosticsMacros`: source text, error codes and how errors are reported |
| `area:syntax` | `RayoSyntax`: lexing, parsing and the syntax tree |
| `area:sema` | `RayoSema`: semantic checking and the checked program |
| `area:ir` | `RayoIR`: the IR and lowering |
| `area:ownership` | `RayoOwnership`: the ownership checks on the IR |
| `area:llvm` | `RayoLLVM`, `RayoRuntime`, `LLVM`, `CLLVM`: emitting LLVM code and the program runtime |
| `area:pipeline` | `RayoCompiler` and `rayoc`: which stages run, and the compiler's command line |
| `area:driver` | `rayo`, `RayoDriver`, `RayoLLVMInstall`: building, linking, running, and finding the toolchain |
| `area:build` | `Package.swift`, CI, install scripts, `TOOLCHAIN.md` and the toolchain's layout |
| `area:spec` | `docs/spec/`, `docs/guide/`, `docs/validation/`, `docs/adr/`, `GLOSSARY.md`, `ROADMAP.md` and `examples/` |
| `area:agents` | `AGENTS.md`, `docs/agents/` and the skills |

If an `area:` label is missing, create it with `gh label create -R rayo-lang/rayo "<label>" --description "<what it covers>"`.
