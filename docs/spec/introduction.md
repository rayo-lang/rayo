# Introduction

Rayo is a general-purpose systems programming language for software that needs control over memory, data layout and the cost of operations. Game engines are one example: they need predictable work and often keep large collections of values with links between them. Rayo lets a program make those choices while keeping ordinary code safe from use-after-free and data races.

The language begins with ownership. For most values, one owner decides when the value is destroyed. Code can pass a value to a new owner or borrow it for a while, and the compiler checks those temporary uses within a function. Some relationships must last longer than a call, such as a game entity keeping a link to another entity. Rayo uses handles and weak pointers for those links; a check at use tells the program when the target is gone. Together, these rules let safe code work without a garbage collector or implicit reference counting.

This specification defines the intended behavior of Rayo, from everyday expressions to the cases that need run-time checks or `unsafe` code. It is for anyone who needs an exact answer about a program, including language users, library authors and implementers. The shorter [guide](../guide/README.md) teaches Rayo through examples; [Why Rayo](../why-rayo.md) explains its design choices. The [validation documents](../validation/README.md) examine the safety argument and demanding use cases, but do not define language behavior.

The chapters start with [values and ownership](01-values-and-ownership.md), then build on that model to explain borrowing, longer-lived links, types, allocation and concurrency. The [specification contents](README.md) provide a path to every chapter when you need to look up a particular rule.
