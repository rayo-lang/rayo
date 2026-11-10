# Writing code

These rules govern how every file, type and function in `Sources/` and `Tests/` is split up and laid out. They bind every line you write or change, and every review. Two skills apply alongside them: `code-design` places a change before you write it, and `code-comments` decides what each comment and name says.

The goal is code a reader takes in at a glance: each file one concept, each type one job, and each function a few logical blocks that say what they do.

## Files

**A file holds one primary type and is named after it.** `Lowering.swift` holds `Lowering`. Beside it, a file may hold only the types that exist to serve its primary type and that no other file names, such as a private helper, or a `Kind` enum that its cases' payloads use.

**A second type that other files use moves to a file of its own.** So a family of data types, such as the AST's expressions, statements and declarations, is one file per type, gathered in a directory named for the family (`Sources/RayoSyntax/AST/`).

**A file past 400 lines splits now**, along the line where its contents stop sharing a reason to change. Data tables, such as `ErrorCode.swift`, are the exception: one entry per case, read by lookup.

## Types

**A type does one job: it has one reason to change.** Split it when it takes on a second one. These show the second job:

- groups of members that read and write separate parts of its state;
- a `// MARK:` section or an extension file that gathers one concern, such as `BodyChecker+Calls.swift`;
- a name that needs *and*, or a vague noun such as *Manager*, *Helper* or *Context*, to cover what it does;
- more than 250 lines, counting every extension of it in every file.

**Splitting a type means giving the concern a type of its own**, with its own state and a narrow interface that the first type calls. Moving members into an extension in another file spreads the type over two files without dividing its job, so it isn't a split. An extension in a file of its own is for a protocol conformance.

## Functions

**A function is tidy: a reader sees what it does at a glance.** It does one job, as one of two kinds:

- **An orchestrator.** Its body is a few blocks, and every line of a block calls or binds a named step, with no mechanics inline.
- **A leaf.** It performs one step, however long its mechanics run.

Extract a function or a value type when a body takes on a second job, however small, or mixes the two kinds. These show it:

- a block whose comment names a job of its own, as a heading would;
- setup followed by dispatch or by detailed mechanics;
- parallel locals assigned through the same branches;
- a body past 50 lines.

A tidy function also has:

- **Inputs from its caller.** A step takes the values its caller already holds as arguments.
- **Results ready to use.** A helper returns what its caller needs, in the shape the caller uses it.
- **Failure in its result.** A step that can fail says so in what it returns or throws, and its caller tests that result before passing it on. A step takes values its caller has already tested, never an optional that it unwraps for the caller.
- **One concern per line.** Related unwraps may share a guard; unrelated checks each take a line, or become a step.
- **Only the cases its inputs reach.** A case that no input reaches, kept only to satisfy a switch, means the type of the input is too wide.

## Blocks

**A function's body is a sequence of logical blocks, separated by one blank line.** A block is one step of the function: the lines in it serve that step and nothing else. A reader skims the blocks to see the steps, then reads the one they need.

**A block of mechanics opens with a one-line comment that says what the step achieves**, in words a reader who hasn't seen the code follows. The comment states the step's purpose, never a translation of each line. An orchestrator's blocks of well-named calls need no comment where the names already say the step.

**A short body is one block.** A leaf of three or four lines that do one thing needs no blank line and no comment.

This body runs four steps without a break, and a reader has to reconstruct them:

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

The same body, with its steps set apart and named:

```swift
private mutating func lowerWhile(_ condition: CheckedExpr, _ body: [CheckedStmt]) {
    let header = newBlock()
    let bodyBlock = newBlock()
    let exit = newBlock()

    // Each pass enters the header, which tests the condition.
    end(with: .goto(header), continuingIn: header)
    end(with: headerTerminator(testing: condition, body: bodyBlock, exit: exit), continuingIn: bodyBlock)

    // A `break` or `continue` in the body leaves through this loop's blocks.
    loops.append(Loop(header: header, exit: exit))
    lower(body)
    loops.removeLast()

    // The body's end goes back to the header, and lowering goes on after the loop.
    end(with: .goto(header), continuingIn: exit)
}
```

## Lines

**A line does one thing a reader takes in at once.** A chain of closures, a ternary inside a call, or a `map` used for its side effect, which the reader has to unpick, becomes a named step or a local named for what it holds.

**Lines stay within 120 columns.** Break a long call at its arguments, one per line, rather than packing a dense expression.

## Before you open a pull request

Audit every file, type and function that you add or change against these rules, and fix what falls short:

- **Every file** holds one primary type, is named after it, and is under 400 lines.
- **Every type** has one job, and is under 250 lines counting all its extensions.
- **Every function** is an orchestrator or a leaf, with each property under [Functions](#functions), and a body under 50 lines.
- **Every body** longer than a few lines is in blocks, and each block of mechanics opens with a comment that says its step.

A file or type you touch that already breaks a rule gets split in a `refactor` pull request of its own, before the change that touches it, so a feature never lands on code that breaks these rules. A reviewer audits the same list, one file, type and function at a time.
