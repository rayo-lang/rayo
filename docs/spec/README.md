# The Rayo specification

Rayo is a general-purpose systems programming language for programs that need control over memory, layout and run-time cost. Safe Rayo code cannot read freed memory or race on data. These guarantees require neither a garbage collector nor implicit reference counting. The rules for ownership and borrowing establish them for values; later chapters carry them through stored links, allocation and concurrency.

This specification defines what a Rayo program means. Read from [chapter 01](01-values-and-ownership.md) to follow the language model from its foundations, or look up a construct when you need its exact rule. Longer chapters have subchapters so related details stay together. The [guide](../guide/README.md) teaches the language through examples.

For a question about a line of code, begin with the construct you wrote. For example, if a call leaves a variable unusable, read [moves](01-values-and-ownership/moves-copies-destruction.md#moves) and [parameters](01-values-and-ownership/parameters.md#parameters). If a returned view cannot be stored, read [dependencies](02-views-and-dependencies.md#dependencies). The [glossary](../../GLOSSARY.md) helps when an error or a rule uses an unfamiliar term.

| If you are looking for… | Read |
| --- | --- |
| Who owns a value, when it moves or copies, and which accesses conflict | [01 Values and ownership](01-values-and-ownership.md) |
| How a view stays valid, or what a result may borrow | [02 Views and dependencies](02-views-and-dependencies.md) |
| A link that lasts beyond a call | [03 Handles and objects](03-handles-and-objects.md) |
| A type, literal, conversion, collection or control-flow expression | [04 Types](04-types.md) |
| A protocol, generic function, closure or function value | [05 Protocols, generics and closures](05-protocols-generics-and-closures.md) |
| Allocation, arena resets or reference counting | [06 Memory and allocators](06-memory-and-allocators.md) |
| Work on another thread, locks, atomics or tasks | [07 Concurrency](07-concurrency.md) |
| A C header, pointer, callback or export | [08 C interop](08-c-interop.md) |
| A constant, conditional build, attribute or reflection | [09 Compile time](09-compile-time.md) |
| A thrown error, panic, check or `unsafe` operation | [10 Errors and safety](10-errors-and-safety.md) |
| Modules, visibility, separate compilation or target requirements | [11 Compilation model](11-compilation-model.md) |
| Whether a sequence of tokens is valid Rayo | [12 Grammar](12-grammar.md) |

The [validation documents](../validation/README.md) check the spec's safety argument and its support for demanding systems patterns. They do not define language behavior.

The spec states the language's intended behavior. Code examples may leave a body out as `{ ... }` when its implementation does not affect the rule being shown; [the grammar](12-grammar.md) gives the source syntax. A numbered link at the end of a rule points to another chapter that supplies part of its meaning.
