---
name: code-style
description: Read before writing, changing or reviewing any code in this repo, every time. Says how code is split into files, types and functions, how a body is laid out in blocks, and the audit every pull request passes.
---

# Code style

These rules decide how the repo's code and tests are split into files, types and functions, and how a function's body is laid out. The aim is code a reader takes in at a glance: each file one concept, each type one job, and each function a few blocks whose steps a reader can see.

## Files

**A file holds one primary type and is named after it.** `Parser.swift` would hold `Parser`. The types that exist only as parts of the primary type stay with it: its kind enum, the payload of one of its cases, or a private helper. `Stmt.swift` would hold `Stmt` and its `StmtKind`, even though a parser builds both.

**A type that stands on its own gets a file of its own**, even when it is small. A type is a part when it is the primary type's kind enum, the payload of one of its cases, or a private helper, and nothing but the primary type and its other parts stores it in a property or a case payload, however much other code builds or reads it. Every other type stands on its own: one that more than one type stores, such as a `BinaryOperator` that a syntax tree's expressions, a checked tree's expressions and an IR's values would all store, and one that is thrown, returned or passed but stored by none, such as an error type that a function only throws. A family of such types, such as the syntax tree's, gathers its files in a directory named for the family, such as `AST/`.

**A file over the limit is split** along the line where its contents stop sharing a reason to change ([Limits](#limits)).

## Types

**A type does one job: it has one reason to change.** The **reasons-to-change test** tells whether two pieces of code, such as two parts of a type or two sites that look alike, are one job: they are one when the same future requirement would change both, and two when either can change without the other. Split a type when it takes on a second job. These show one:

- a group of members that reads and writes state the rest of the type doesn't touch, whether it sits under a `// MARK:` or in an extension file;
- a name that needs *and*, or a vague noun such as *Manager*, *Helper* or *Context*, to cover what it does;
- a type over the limit ([Limits](#limits)).

**Splitting a type gives the second job a type of its own**, with its own state and a narrow interface that the first type calls. Moving members into an extension in another file spreads the type over two files and leaves its job whole, so it is no split. A file of its own holds an extension only for a protocol conformance, named `Type+Protocol.swift`. A private extension of another type, inside the file that uses it, is fine.

## Functions

These rules cover every body: functions, initializers, accessors, subscripts and closures.

**A function does one job, as one of two kinds:**

- **An orchestrator** calls a function for each step of its job. Each line calls a step, binds a step's result, tests a step's result or one of its own arguments in a `guard`, `if` or `switch`, or returns. Passing a value to a step, or reading a field of a step's result, is part of calling or testing it.
- **A leaf** does its job with mechanics. It reads and writes its own state and arguments, and calls primitives: standard-library operations, and members of its own type that only read or write its stored state, such as `advance()`, `newBlock()` or `end(with:)`. A leaf may also call its helpers and recurse on part of its input, as `lowerWhile` under [Blocks](#blocks) calls `headerTerminator` and `lower(body)`. Building a value with an initializer or a literal is mechanics, unless the initializer does a step of the job. A body with any line of mechanics is a leaf, and it may run in several blocks.

This orchestrator runs three steps, and tests each result before the next:

```swift
func compile(_ source: [UInt8]) -> (program: IRProgram?, diagnostics: [Diagnostic]) {
    let (file, syntaxErrors) = parse(source)
    guard syntaxErrors.isEmpty else { return (nil, syntaxErrors) }

    let (checked, checkErrors) = check(file)
    guard let checked else { return (nil, checkErrors) }

    return (lower(checked), [])
}
```

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

**A leaf's block of more than one line opens with a one-line comment that says what the block achieves**, in the terms of the function's job, so a reader skims the steps without rebuilding each from its lines. It describes the block whole, never one line of it: "Push the loop, lower the body, then pop the loop" reads the lines back, where "Lower the body with this loop innermost" says the step. An orchestrator's blocks take no comment, since its call names say its steps. A body of one step is one block, and takes no opening comment of its own.

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

**A leaf explains its algorithm in its body, case by case.** Its doc comment says only what it does, as a black box (the `code-comments` skill), so the body is where a reader learns how. Each case the body tells apart opens with a comment, one line where one will do, that says which case it is and what the function does with it, in the terms of the function's job:

- each case of a `switch`;
- each `if`, and each of its `else` branches;
- each test that leaves early: a `guard`, a `continue`, a `break` out of a loop, an early `return`, or a `throw`.

This holds in a body of one block as much as in one of several. When a block opens with a case, the case's comment opens the block too. The one exception is a `switch` that only maps each case to a value, one line per case: its patterns and values say it all. An orchestrator's cases take no comment either, since the step each one calls names it.

This leaf drops the newlines that only break a line. Its doc comment says that much, and each case and each test of a newline says which rule it applies:

```swift
/// Keeps the newlines that end a statement, and drops those that only break a line.
static func significantNewlines(_ raw: [Token]) -> [Token] {
    var result: [Token] = []
    var brackets: [Punct] = []
    for (index, token) in raw.enumerated() {
        switch token.kind {
        // An opening bracket becomes the innermost one, which decides what a newline inside it means.
        case .punct(let bracket) where bracket == .lparen || bracket == .lbrace:
            brackets.append(bracket)

        // A closing bracket ends the innermost one; a stray one ends nothing.
        case .punct(.rparen), .punct(.rbrace):
            _ = brackets.popLast()

        // A newline is kept where it ends a statement, and each `continue` drops it where the statement goes on.
        case .newline:
            // Where `(` is the innermost bracket, a call's arguments and a grouped expression run across lines.
            if brackets.last == .lparen { continue }
            // A line that ends in a binary or assignment operator, `->`, `(` or `{` runs on into the next.
            if let previous = result.last, continuesLine(previous) { continue }
            // A line that starts with `->`, `{`, `else`, or a binary operator other than `-` joins the line above;
            // a `-` there starts a negation.
            if index + 1 < raw.count, joinsLine(raw[index + 1]) { continue }
            // A blank line, or a newline before the first statement, ends nothing.
            if result.isEmpty || result.last?.kind == .newline { continue }

        // Every other token needs no bookkeeping.
        default:
            break
        }

        // Keep every token that no test above dropped.
        result.append(token)
    }
    return result
}
```

## Lines

**A line does one thing that a reader takes in at once.** Related unwraps may share a guard. Unrelated checks each take a line, or become a step. A chain of closures, a ternary or a `map` used for its side effect that a reader has to unpick becomes a named step, or a local named for what it holds.

**A line fits in 120 columns.** A longer call breaks at its arguments.

## Limits

**A file holds at most 400 lines, a type at most 250, and a function body at most 50.** Only lines of code count: a line holding only whitespace or a comment doesn't. A type counts its nested types and every extension of it in the module. The numbers are SwiftLint's `file_length`, `type_body_length` and `function_body_length` defaults, with two changes: blank and comment lines never count, and a type counts its extensions, so moving code into an extension file doesn't hide its size.

**A data table is exempt from the limits.** A data table is a type whose body is one declaration per case with no logic between them, such as an enum of error codes, or a test's `arguments:` table. Its lines count toward no file, type, suite or test. Every other rule still applies to it.

## Tests

**A test file is named for the behaviour it covers**, such as `MoveTests.swift`, and may hold several suites of that behaviour. For test files, this replaces the file rule under [Files](#files). Each suite counts as a type for the limits. A helper that several test files share goes in a file named for what it helps with.

## Before you open a pull request

Audit every file, type and function you add or change against this list, and fix what falls short:

- **Every file** holds one primary type and its parts and is named after it (a test file is named for the behaviour its suites cover), and is within the limits.
- **Every type** does one job, and is within the limits.
- **Every function** is an orchestrator or a leaf, with each property under [Functions](#functions), and is within the limits.
- **Every doc comment** describes its declaration as a black box: it names no step, test, state or helper of the body.
- **Every body** with more than one step runs its steps as blocks separated by a blank line, and each leaf block of more than one line opens with its comment.
- **Every case** a leaf tells apart — a `switch` case, an `if` or `else` branch, a test that leaves early — opens with its comment, unless it is a `switch` that only maps each case to a value.
- **Every line** does one thing and fits in 120 columns.

**Before you change a file, type or function that already breaks a rule, split or tidy it in a `refactor` pull request of its own**, and stack your change on it: open your change with the refactor's branch as its base. A reviewer audits the same list, one file, type and function at a time.
