---
name: code-style
description: Read before writing, changing or reviewing any code in this repo, every time. Says which compiler stage code goes in, how it is split into files, types and functions, how a body is laid out in blocks, which forms of current Swift it uses, and the audit every pull request passes.
---

# Code style

These rules decide which stage a change to the compiler goes in, how the repo's code and tests are split into files, types and functions, and how a function's body is laid out. The aim is code a reader takes in at a glance: each stage its own questions, each file one concept, each type one job, and each function a few blocks whose steps a reader can see.

## Stages

**A compiler runs in stages, and each stage owns a set of questions about the program**, such as what the text says, what it means, or what each place holds on each path through a function. **A change goes in the stage that owns the question it decides.** That stage answers the question whole and reports every error the answer gives. A later stage takes an earlier stage's answers as given, and an earlier stage leaves a later stage's questions to it, even where it holds all it would take to answer them.

A type checker that reports a move out of a borrowed parameter answers the ownership pass's question, however little code the rule takes there, so the rule is in the wrong stage. The project says, in its own docs, which of its stages owns which questions.

## Files

**A file holds one primary type and is named after it, or extends it as one of the extension files below.** `Parser.swift` would hold `Parser`. The types that exist only as parts of the primary type stay with it: its kind enum, the payload of one of its cases, or a private helper. `Stmt.swift` would hold `Stmt` and its `StmtKind`, even though a parser builds both.

**A type that stands on its own gets a file of its own**, even when it is small. A type is a part when it is the primary type's kind enum, the payload of one of its cases, or a private helper, and nothing but the primary type and its other parts stores it in a property or a case payload, however much other code builds or reads it. Every other type stands on its own: one that more than one type stores, such as a `BinaryOperator` that a syntax tree's expressions, a checked tree's expressions and an IR's values would all store, and one that is thrown, returned or passed but stored by none, such as an error type that a function only throws. A family of such types, such as the syntax tree's, gathers its files in a directory named for the family, such as `AST/`.

**A type may spread over extension files, one area of its job to each.** Its stored properties live in `Type.swift`, and each extension file holds one area of the job and is named `Type+Area.swift` for it: a parser's `Parser+Expressions.swift`, or a protocol conformance's `Type+Protocol.swift`. A private extension of another type, inside the file that uses it, is fine.

**A file over the limit is split** ([Limits](#limits)): contents with different reasons to change go to types of their own, and one type's one job spreads over `Type+Area.swift` extension files.

## Types

**A type does one job: it has one reason to change.** The **reasons-to-change test** tells whether two pieces of code, such as two parts of a type or two sites that look alike, are one job: they are one when the same future requirement would change both, and two when either can change without the other. Split a type when it takes on a second job. These show one:

- a group of members that reads and writes state the rest of the type doesn't touch, whether it sits under a `// MARK:` or in an extension file;
- a name that needs *and*, or a vague noun such as *Manager*, *Helper* or *Context*, to cover what it does.

**Splitting a type gives the second job a type of its own**, with its own state and a narrow interface that the first type calls. Moving members into an extension in another file leaves the type's job whole, so it is no split: it only organizes the job over files ([Files](#files)).

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

**A leaf's block opens with a comment when its step isn't plain from its lines**, so a reader skims the steps without rebuilding each one. An orchestrator's blocks and cases rarely need a comment, since its call names say its steps.

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

The same leaf, with its steps set apart, and the steps that aren't plain from their lines said:

```swift
private mutating func lowerWhile(_ condition: CheckedExpr, _ body: [CheckedStmt]) {
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

**A leaf explains its algorithm in its body**, since its doc comment says what it does, not how. Where a case it tells apart — a `switch` case, a branch, an early exit — carries a rule the reader couldn't read off its condition, a comment on it says the rule.

This leaf drops the newlines that only break a line. Its doc comment says that much, and the cases whose rules aren't plain from their code say them:

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

        default:
            break
        }

        result.append(token)
    }
    return result
}
```

## Lines

**A line does one thing that a reader takes in at once.** Related unwraps may share a guard. Unrelated checks each take a line, or become a step. A chain of closures, a ternary or a `map` used for its side effect that a reader has to unpick becomes a named step, or a local named for what it holds.

**A line fits in 120 columns.** A longer call breaks at its arguments.

## Swift

**Code is written in the newest Swift that Swift 6.4 compiles, in the Swift 6 language mode, for macOS 27 and later, Linux and Windows.** Each rule here names the current form and the older one it replaces, wherever the older one would go. Code uses only what plain `swift build` compiles: a form behind a compiler flag (`-enable-experimental-feature`, `-enable-upcoming-feature`) or an underscored name (`@_lifetime`, `_read`) is outside the language.

**A value a `switch` or `if` picks is an expression**, in place of a `var` assigned in each branch or a `return` in each case. The `switch` or `if` is the body's one expression, follows `return`, or is bound with `let`, so `return` stands once, before it, and never inside one of its cases. A branch is one expression, a `throw`, or a call that never returns; a branch that needs statements is a step to extract. A body of one expression leaves out `return`.

```swift
/// Describes the token the parser found, the way an error message names it.
private func found(_ token: Token) -> FoundToken {
    switch token.kind {
    case .newline: .newline
    case .eof: .endOfFile
    default: .token(token.description)
    }
}
```

**Ownership is in the types.**

- **A `~Copyable` struct takes the place of a class wherever one owner holds the value at a time.** That covers a value whose identity matters, such as a cursor, a builder or a table that each step updates in turn, and one that must be released, such as an LLVM handle, whose `deinit` releases it. A step that updates such a value takes it `inout` for the length of the call, in place of holding a reference to a shared instance. A class stays only where a struct can't stand in for it: several holders keep one instance at once and each sees the others' changes, a type inherits, or a reference is `weak`.
- **A `consuming` method that hands the value on ends it with `discard self`**, which a type allows only when its stored properties are all trivial, such as handles and integers: a `String`, array or class field rules it out.
- **A function takes a noncopyable value `borrowing`** when it only reads it, and `consuming` when it keeps or ends it. A copyable parameter keeps the default convention: `borrowing` on one forbids even the copy a `for` loop over it makes.
- **`consume x` marks the last use of a local that must not be used after it**, such as a noncopyable value or a buffer handed to its owner, so the compiler rejects any later use.
- **A computed property that hands out a stored value reads it with a `borrow` accessor**, in place of `get`, and, when callers write it, writes it with a `mutate` accessor, in place of `set`. `borrow` pairs with `mutate` alone. The accessor returns a stored property of the struct or enum itself, a class's `let`, another property with such accessors, or a global `let`; a class's `var` keeps `get` and `set`.
- **`MutableRef(&value)` holds one place for several updates**, such as `MutableRef(&counts[key, default: 0])`, in place of a lookup per update; `Ref(value)` reads one the same way.
- **A noncopyable type can't be a tuple's element, an `Array`'s element or `CustomStringConvertible`.** A buffer of them is a `UniqueArray`, and `Optional.take()` moves one out of an optional. A recursive enum whose values are copied or stored in arrays, such as a syntax tree, stays `indirect` and copyable.

```swift
/// An LLVM module this compiler owns, disposed of when its owner is done with it.
struct OwnedModule: ~Copyable {
    private let ref: LLVMModuleRef

    init(_ ref: LLVMModuleRef) { self.ref = ref }

    deinit { LLVMDisposeModule(ref) }

    /// Hands the module to an owner that disposes of it in its turn, such as an execution engine.
    consuming func release() -> LLVMModuleRef {
        let ref = self.ref
        discard self
        return ref
    }
}
```

**Memory goes through spans and the unique types.**

- **Contiguous storage is read through a `Span`** (`array.span`, `string.utf8.span`, `string.utf8Span`), in place of `withUnsafeBufferPointer`, and written through a `MutableSpan` or an `OutputSpan` (`Array(capacity:initializingWith:)`, `withTemporaryAllocation`), in place of `Array(unsafeUninitializedCapacity:)` and unsafe scratch buffers.
- **A span is bound where it is used**: a span to a `let` before a `for` loop runs over it, and a mutable span to a `var` before it is written through. A run of reads or writes that would otherwise go through an unsafe buffer goes through such a binding; a loop over an array's elements, and a single `xs[i]`, which already writes in place, stay as they are.
- **A function takes a span as a parameter, and its caller makes it**, since returning one takes `@_lifetime`, which is outside the language.
- **A heap value with one owner is a `UniqueBox`**, in place of a `final class` that boxes it, and a growable buffer with one owner a `UniqueArray`. A buffer of fixed size is an `InlineArray`, written `[N of T]`, in place of a tuple of one type.
- **Unsafe pointers appear only in calls to LLVM's C API**: an out-parameter the call fills, or a buffer held inside the narrowest `withUnsafe…` closure.

**Errors are typed.** A function that throws one kind of error names it, as in `throws(ParseFailure)`, in place of a bare `throws`, and a generic `throws(E)` takes the place of `rethrows`. A `do` whose block holds a `throw` statement is `do throws(E)`, so its `catch` gets `E` rather than `any Error`; a block that only `try`s calls that throw `E` gets `E` already. One `catch` that switches on the error takes the place of a `catch` per case, which the compiler doesn't check for exhaustiveness.

**The smaller forms:**

- `count(where:)` counts, in place of `filter { … }.count` or a loop.
- `"\(value, default: "none")"` interpolates an optional, in place of `value.map { "\($0)" } ?? "none"`.
- `Mutex` and `Atomic`, from `Synchronization`, guard state that threads share, in place of a lock.
- A list that runs over several lines, of arguments, parameters or a literal's items, ends with a trailing comma, in place of a last item that ends without one.
- An existential is spelled `any P`, in place of a bare `P`.
- `package` marks a declaration that only this package's modules share, in place of `public`. `internal import` brings in a module that only the importing module's implementation uses, and `package import` one whose types its `package` declarations show.

**Tests use Swift Testing's current forms.**

- **A raw identifier names a test once**, as in ``@Test func `a stray brace is reported`()``, in place of a display string beside a camelCase name. A name that holds a backslash, or would push its `func` line past 120 columns, keeps the display string.
- **`#require` unwraps**, in place of `!`.
- **`#expect(throws:)` returns the error it caught**, for the test to check, in place of a `do`/`catch`. Its closure can't consume a noncopyable value it captures, so a test of a `consuming` call catches the error in a `do`.
- **An exit test, `#expect(processExitsWith:)`, checks a trap in `rayoc` itself** without ending the run; a program a test compiles still runs as a process of its own.

## Limits

**A file holds at most 1000 lines, and a function body at most 50.** Only lines of code count: a line holding only whitespace or a comment doesn't. The numbers are SwiftLint's `file_length` error threshold and `function_body_length` warning default. A type has no limit of its own: [Types](#types) bounds it by its one job.

**A data table is exempt from the limits.** A data table is a type whose body is one declaration per case with no logic between them, such as an enum of error codes, or a test's `arguments:` table. Its lines count toward no file or test. Every other rule still applies to it.

## Tests

**A test file is named for the behaviour it covers**, such as `MoveTests.swift`, and may hold several suites of that behaviour. For test files, this replaces the file rule under [Files](#files). A helper that several test files share goes in a file named for what it helps with.

## Before you open a pull request

Audit every file, type and function you add or change against this list, and fix what falls short:

- **Every file, type and function** lies in the stage that owns the questions it decides, so no stage answers a question another stage owns.
- **Every file** holds one primary type and its parts and is named after it (an extension file holds one area of its type's job and is named `Type+Area.swift`, with the type's stored properties in `Type.swift`; a test file is named for the behaviour its suites cover), and is within the limits.
- **Every type** does one job.
- **Every function** is an orchestrator or a leaf, with each property under [Functions](#functions), and is within the limits.
- **Every body** with more than one step runs its steps as blocks separated by a blank line, and a reader can follow each leaf's steps and cases, with a comment wherever the lines alone don't say them.
- **Every line** does one thing and fits in 120 columns.
- **Every construct** is the form a rule under [Swift](#swift) names, in place of the one it replaces, and no target enables a language feature (`enableExperimentalFeature`, `enableUpcomingFeature`).
- **Every comment and name** passes the `code-comments` skill's audit.

**Before you change a file, type or function that already breaks a rule, split or tidy it in a `refactor` pull request of its own**, and stack your change on it: open your change with the refactor's branch as its base. A reviewer audits the same list, one file, type and function at a time.
