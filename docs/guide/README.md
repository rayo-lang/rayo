# The Rayo guide

This guide teaches Rayo step by step, for programmers who know C++, Rust, Swift or C#. Each chapter starts from a problem that systems code has, solves it in Rayo, and ends with links to the spec sections that hold the full rules.

Read the chapters in order: each one builds on the ones before it. A code sample may put statements beside declarations, or leave a body out as `{ ... }`, to keep it short. In a source file, statements go inside a function body. The [spec](../spec/) states every rule exactly, and the [glossary](../../GLOSSARY.md) says in a sentence what each term means.

| Chapter | Teaches |
| --- | --- |
| [1 Basics](01-basics.md) | Functions, structs, enums and `when`, optionals, lists and loops, closures, protocols and generics, strings and errors |
| [2 Moves and copies](02-moves-and-copies.md) | Owners, moves, written-out copies, destruction and `deinit` |
| [3 Borrowing](03-borrowing.md) | Parameter conventions, bindings of places, `&`, and the law of exclusivity |
| [4 Views](04-views.md) | Spans and other views, what a function's result may borrow, and why no view outlives what it borrows |
| [5 Handles and objects](05-handles-and-objects.md) | Links that outlive a function: pools and handles, objects and weak pointers |
| [6 Memory and allocators](06-memory-and-allocators.md) | Allocators as values, arenas and resets, `Box`, and reference counting with `Shared` |
| [7 Concurrency](07-concurrency.md) | Lending work to other threads, `Sendable`, locks, threads and stepped tasks |
| [8 C and compile time](08-c-and-compile-time.md) | Calling C and being called from it, `unsafe`, `const`, `static if` and reflection |
