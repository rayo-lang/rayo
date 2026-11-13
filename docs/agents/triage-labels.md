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

**Every triaged issue carries an `area:` label for each part of the project its work changes**: one for a change inside one module, several for a change that crosses stages. An epic takes none, since its sub-issues carry theirs. The compiler's areas are its stages, and each label matches the commit scope for that code, so an issue's labels and its pull request's scope agree.

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
| `area:build` | `Package.swift`, CI, install scripts and the toolchain's layout |
| `area:spec` | `docs/spec/`, `docs/guide/`, `GLOSSARY.md` and `ROADMAP.md` |
| `area:agents` | `AGENTS.md`, `docs/agents/` and the skills |

[compiler-stages.md](compiler-stages.md) says what each compiler stage owns. Label an issue with the stage that owns the question it decides, and with each other stage whose code it changes.

If an `area:` label is missing, create it with `gh label create -R rayo-lang/rayo "<label>" --description "<what it covers>"`.
