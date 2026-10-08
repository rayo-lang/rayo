# The Rayo guide

This guide is for programmers who already know C++, Rust, Swift or C# and want to write Rayo. It starts with ordinary code, then follows a game through ownership, borrowed data, stored links, memory and concurrency. You can read it from start to finish without learning the full memory model first.

If you come from **C++**, pay particular attention to chapters 2 to 5: they show what replaces implicit copies, references and pointers kept after a call. If you come from **Rust**, chapters 3 to 5 show how Rayo checks borrows within a function and uses checked links when a relationship lasts longer. If you come from **Swift or C#**, chapters 2 and 6 show when values move, how they are destroyed, and where allocations come from. These are starting points, not separate versions of the language.

Read the chapters in order when learning Rayo. If you need an exact rule, use the [spec](../spec/README.md); its chapters stand alone and keep the exceptions beside the rules. The [glossary](../../GLOSSARY.md) gives a short definition of each term. A code sample here may put statements beside declarations, or leave a body out as `{ ... }`, to keep it short. In a source file, statements go inside a function body.

| Chapter | Teaches |
| --- | --- |
| [1 Basics](01-basics.md) | Variables, numbers and their conversions, structs, functions, `if`, and loops |
| [2 Moves and copies](02-moves-and-copies.md) | Owners, moves, `copy` and `clone()`, and when values are destroyed |
| [3 Borrowing](03-borrowing.md) | Parameter conventions, `borrow` and `&` in declarations, and the law of exclusivity |
| [4 Views](04-views.md) | Spans and other views, what a function's result may borrow, and why no view outlives what it borrows |
| [5 Handles and objects](05-handles-and-objects.md) | Links that outlive a function: pools and handles, objects and weak pointers |
| [6 Memory and allocators](06-memory-and-allocators.md) | Allocators as values, arenas and resets, `Box`, and reference counting with `Shared` |
| [7 Concurrency](07-concurrency.md) | Lending work to other threads, `Sendable`, locks, threads and stepped tasks |
| [8 C and compile time](08-c-and-compile-time.md) | Calling C and being called from it, `unsafe`, `const`, `static if` and reflection |
