# Code style

These rules decide how the code in `Sources/` and `Tests/` is split into files, types and functions, and how a function's body is laid out. The aim is code a reader takes in at a glance: each file one concept, each type one job, and each function a few blocks whose steps a reader can see.

## Files

**A file holds one primary type and is named after it.** `Lowering.swift` holds `Lowering`. The types that exist only as parts of the primary type stay with it: its kind enum, the payload of one of its cases, or a private helper. `Stmt.swift` holds `Stmt` and `StmtKind`, even though the parser builds both.

**A type that stands on its own gets a file of its own**, even when it is small. A type stands on its own when more than one type stores it, as `ExprKind`, `CheckedExprKind` and `Rvalue` all store `BinaryOperator`. A type that only the primary type and its parts store is a part, however much other code builds or reads it. A family of such types, such as the AST's, gathers its files in a directory named for the family (`Sources/RayoSyntax/AST/`).

**A file over the limit is split** along the line where its contents stop sharing a reason to change ([Limits](#limits)).

## Types

**A type does one job: it has one reason to change**, as `code-design`'s reasons-to-change test decides. Split it when it takes on a second job. These show one:

- a group of members that reads and writes state the rest of the type doesn't touch, whether it sits under a `// MARK:` or in an extension file;
- a name that needs *and*, or a vague noun such as *Manager*, *Helper* or *Context*, to cover what it does;
- a type over the limit ([Limits](#limits)).

**Splitting a type gives the second job a type of its own**, with its own state and a narrow interface that the first type calls. Moving members into an extension in another file spreads the type over two files and leaves its job whole, so it is no split. A file of its own holds an extension only for a protocol conformance, named `Type+Protocol.swift`. A private extension of another type, inside the file that uses it, is fine.

## Functions

These rules cover every body: functions, initializers, accessors, subscripts and closures.

**A function does one job, as one of two kinds:**

- **An orchestrator** calls a function for each step of its job. Each line calls a step, binds a step's result, tests that result in a `guard`, `if` or `switch`, or returns it, as `Driver.checkAndLower` does.
- **A leaf** does its job with mechanics. It reads and writes its own state and arguments, and calls primitives: standard-library operations, and members of its own type that only read or write its stored state, such as `advance()`, `newBlock()` or `end(with:)`. A leaf may also call its helpers and recurse on part of its input, as `lowerWhile` calls `headerTerminator` and `lower(body)`. A body with any line of mechanics is a leaf, and it may run in several blocks.

**A body that takes on a second job gets a function extracted.** These show it:

- a block whose opening comment could be a function's doc comment, with inputs and a result of its own;
- mechanics that build values, followed by a `switch` that hands them to different steps;
- parallel locals assigned through the same branches;
- a body over the limit ([Limits](#limits)).

A tidy function also has:

- **Inputs from its caller.** A step takes the values its caller already holds as arguments.
- **Results ready to use.** A helper returns what its caller needs, in the shape the caller uses it.
- **Failure in its result.** A step that can fail says so in what it returns or throws. Its caller tests that result, and passes the step after it a value already tested, never an optional to unwrap.

## Blocks

**A body with more than one step runs its steps as blocks, separated by one blank line.** A block is one step: every line in it serves that step. A reader skims the blocks to see the steps, then reads the one they need.

**A leaf's block of more than one line opens with a one-line comment that says what the block achieves.** `code-comments` says how to write it. An orchestrator's blocks take no comment, since its call names say its steps. A body of one step is one block, and takes no comment of its own.

This leaf builds a loop in four steps, and runs them as one block, so a reader rebuilds the steps from the lines:

```swift
private mutating func lowerWhile(_ condition: CheckedExpr, _ body: [CheckedStmt]) {
    let header = newBlock()
    let bodyBlock = newBlock()
    let exit = newBlock()
    end(with: .goto(header), continuingIn: header)
    end(with: headerTerminator(testing: condition, body: bodyBlock, exit: exit), continuingIn: bodyBlock)
    loops.append(Loop(header: header, exit: exit))
    lower(body)
    loops.removeLast()
    end(with: .goto(header), continuingIn: exit)
}
```

The same leaf, with its steps set apart and said:

```swift
private mutating func lowerWhile(_ condition: CheckedExpr, _ body: [CheckedStmt]) {
    // Make the loop's blocks: its header, its body, and its exit.
    let header = newBlock()
    let bodyBlock = newBlock()
    let exit = newBlock()

    // Enter the loop at its header, which tests the condition and goes on to the body or the exit.
    end(with: .goto(header), continuingIn: header)
    end(with: headerTerminator(testing: condition, body: bodyBlock, exit: exit), continuingIn: bodyBlock)

    // Lower the body with this loop innermost, so its `break` goes to `exit` and its `continue` to `header`.
    loops.append(Loop(header: header, exit: exit))
    lower(body)
    loops.removeLast()

    // The body's end goes back to the header, and lowering goes on after the loop.
    end(with: .goto(header), continuingIn: exit)
}
```

## Lines

**A line does one thing that a reader takes in at once.** Related unwraps may share a guard. Unrelated checks each take a line, or become a step. A chain of closures, a ternary or a `map` used for its side effect that a reader has to unpick becomes a named step, or a local named for what it holds.

**A line fits in 120 columns.** A longer call breaks at its arguments.

## Limits

**A file holds at most 400 lines, a type at most 250, and a function body at most 50.** Only lines of code count: a line holding only whitespace or a comment doesn't. A type counts its nested types and every extension of it in the module. The numbers are SwiftLint's `file_length`, `type_body_length` and `function_body_length` defaults, with two changes: blank and comment lines never count, and a type counts its extensions, so moving code into an extension file doesn't hide its size.

**A data table is exempt from the limits.** A data table is a type whose body is one declaration per case with no logic between them, such as `ErrorCode`, whose lines don't count toward its file or its type, or a test's `arguments:` table, whose lines don't count toward its file or its suite. Every other rule still applies to it.

## Tests

**A test file is named for the behaviour it covers**, such as `MoveTests.swift`, and may hold several suites of that behaviour. In `Tests/`, this replaces the file rule under [Files](#files). Each suite counts as a type for the limits. A helper that several test files share goes in a file named for what it helps with.

## Before you open a pull request

Audit every file, type and function you add or change against this list, and fix what falls short:

- **Every file** holds one primary type and its parts and is named after it (in `Tests/`, is named for the behaviour its suites cover), and is within the limits.
- **Every type** does one job, and is within the limits.
- **Every function** is an orchestrator or a leaf, with each property under [Functions](#functions), and is within the limits.
- **Every body** with more than one step runs its steps as blocks separated by a blank line, and each leaf block of more than one line opens with its comment.
- **Every line** does one thing and fits in 120 columns.

**Before you change a file, type or function that already breaks a rule, split or tidy it in a `refactor` pull request of its own**, and stack your change on it (`AGENTS.md`, "Pull requests"). A reviewer audits the same list, one file, type and function at a time.
