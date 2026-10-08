# The Rayo guide

Start with the [Introduction](introduction.md), then read the chapters in order. They follow examples from a game, adding each language feature when the code needs it. For a complete account of a rule, use the [specification](../spec/README.md); the [glossary](../../GLOSSARY.md) gives a short definition of each term.

A code sample here may put statements beside declarations, or leave a body out as `{ ... }`, to keep it short. In a source file, statements go inside a function body.

| Chapter | Teaches |
| --- | --- |
| [Introduction](introduction.md) | What Rayo is and how to learn it through this guide |
| [1 Basics](01-basics.md) | Variables, numbers and their conversions, structs, functions, `if`, and loops |
| [2 Moves and copies](02-moves-and-copies.md) | Owners, moves, `copy` and `clone()`, and when values are destroyed |
| [3 Borrowing](03-borrowing.md) | Parameter conventions, `borrow` and `&` in declarations, and the law of exclusivity |
| [4 Views](04-views.md) | Spans and other views, what a function's result may borrow, and why no view outlives what it borrows |
| [5 Handles and objects](05-handles-and-objects.md) | Links that outlive a function: pools and handles, objects and weak pointers |
| [6 Memory and allocators](06-memory-and-allocators.md) | Allocators as values, arenas and resets, `Box`, and reference counting with `Shared` |
| [7 Concurrency](07-concurrency.md) | Lending work to other threads, `Sendable`, locks, threads and stepped tasks |
| [8 C and compile time](08-c-and-compile-time.md) | Calling C and being called from it, `unsafe`, `const`, `static if` and reflection |
