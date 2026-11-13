# Compiler stages

`rayoc` compiles a file in stages, each in one or more Swift modules of its own, and the `code-style` skill puts each change in the stage that owns the question it decides. This page says what each stage owns: what it decides, and what it leaves to the others. `Package.swift` says which stage may use which, and [TOOLCHAIN.md](../../TOOLCHAIN.md#layout) what each module holds.

**A question that fits no stage below widens one, or makes a new one, and the change says so here**, so this page keeps naming an owner for every question the compiler answers.

## Source and diagnostics: `RayoSource`, `RayoDiagnostics`, `RayoDiagnosticsMacros`

**Decides:** positions and ranges in the source text, and the errors the compiler can report, each with its code and message.

**Leaves to the others:** when an error is reported, and at which range of the source: the stage that finds it decides both.

## Syntax: `RayoSyntax`

**Decides:** what the program says: how the text reads as tokens, where each statement ends, and how the tokens make the syntax tree. It reports text that doesn't read as a program, such as a block left unclosed.

**Leaves to the others:** what the program means. It knows no names and no types, so `a.b` is a member of whatever `a` turns out to be.

## Semantic checking: `RayoSema`

**Decides:** what the program means: what each name refers to, each expression's type, and what each expression does, including which uses of a value are moves and which are reads, which places the code may change, that an expression standing as a statement is Void, and what the syntax alone says about where a function can run, such as a body that reaches its end without a `return`. It also decides how each type lies in memory: its size and alignment, and a struct's field order and each field's offset. It reports a program that means nothing or the wrong thing, and produces the checked program.

**Leaves to the others:** what a function's places hold over its paths, and every rule about it: it marks each move, and the ownership pass decides whether the move is allowed.

## Lowering: `RayoIR`

**Decides:** how the checked program runs as control flow: its blocks and branches, the order its operands are evaluated in, the temporaries that hold the values between, and each move and read written out where it happens.

**Leaves to the others:** every rule: it reports no errors, and lowers every checked program.

## Ownership: `RayoOwnership`

**Decides:** every rule about values over the paths of a function: whether a value is there when it's used, whether a move is allowed, such as one out of a borrowed parameter, a use after a move, a `let` assigned again, and a value stored in a place that no path then reads.

**Leaves to the others:** which uses are moves, which semantic checking decides and lowering writes out, and what the program means.

## Emitting: `RayoLLVM`, `RayoRuntime`, `LLVM`, `CLLVM`

**Decides:** how the program is written as LLVM code: the LLVM type of each Rayo type, which maps the layout semantic checking decides onto LLVM's types, how each function's arguments and result are passed, and how values move between places, how the build mode changes the code, such as overflow that panics in a debug build, and the runtime each program links.

**Leaves to the others:** every rule of the language, how each type lies in memory among them. It reports no error in a program, since every program that reaches it was accepted.

## The pipeline: `RayoCompiler`, `rayoc`

**Decides:** which stages run for what `rayoc` is asked, in which order, and that each stops the compile when it reports errors, so a stage sees only a program that every stage before it accepted. It also decides what the output asks of a program, such as a `main` for an executable, and what `rayoc` reads, writes and prints.

**Leaves to the others:** every question about what the program says or means.

The driver, `rayo`, in `RayoDriver` and `RayoLLVMInstall`, runs `rayoc` and links the object code it writes: it lies outside `rayoc`'s stages.

## Not yet in its stage

Code that answers another stage's question today. A change that touches it moves it to its stage first, and takes it off this list.

None today.
