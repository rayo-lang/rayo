import Testing
import RayoCompiler
import RayoDiagnostics
import RayoSyntax

/// Shapes code nests in, each written `levels` levels deep, as the statements of `main` after its locals.
private enum Shape: CaseIterable {
    /// `0 + 1 + 1 + …`, which the parser builds in a loop, and whose first `+` is the innermost.
    case sum
    /// `((…(1)…))`, which the parser alone recurses into, since the checked program keeps no parentheses.
    case parentheses
    /// `!!…!true`, a prefix operator on a prefix operator.
    case negations
    /// `f(x: f(x: …1…))`, a call whose argument is a call.
    case calls
    /// `xs[xs[…[0]…]]`, an element whose index is an element.
    case elements
    /// `f(x: …if b { f(x: …1…) } else { 0 }…)`: calls around an `if`, and calls in the block whose value it gives,
    /// each about half the levels.
    case callsInIf
    /// `if b { if b { …0… } else { 0 } } else { 0 }`: an `if` that is the value of the block around it, in turn.
    case ifValues
    /// `if b {} else if b {} … else {}`, whose each `else if` arm lies a block deeper than the arm before it.
    case elseIfChain
    /// `if b { if b { … } }`, an `if` statement in the block of the `if` around it.
    case ifStatements
    /// `while b { while b { … } }`, a loop in a loop's body.
    case loops
    /// `while b { … _ = f(x: f(x: …1…)) … }`: loops, and calls in the innermost body, each about half the levels.
    case callsInLoops

    func code(levels: Int) -> String {
        switch self {
        case .sum, .parentheses, .negations, .calls, .elements, .callsInIf, .ifValues:
            valueBinding + expression(levels: levels) + "\n    print(value)"
        case .elseIfChain: "if b {}" + String(repeating: " else if b {}", count: levels - 1) + " else {}"
        case .ifStatements: String(repeating: "if b { ", count: levels) + String(repeating: "}", count: levels)
        case .loops: String(repeating: "while b { ", count: levels) + String(repeating: "}", count: levels)
        case .callsInLoops:
            String(repeating: "while b { ", count: levels / 2) + "_ = "
                + Shape.calls.expression(levels: levels - levels / 2) + String(repeating: " }", count: levels / 2)
        }
    }

    /// The expression the shape binds to `value`, for a shape that nests as an expression.
    private func expression(levels: Int) -> String {
        switch self {
        case .sum: "0" + String(repeating: " + 1", count: levels)
        case .parentheses: String(repeating: "(", count: levels) + "1" + String(repeating: ")", count: levels)
        case .negations: String(repeating: "!", count: levels) + "true"
        case .calls: String(repeating: "f(x: ", count: levels) + "1" + String(repeating: ")", count: levels)
        case .elements: String(repeating: "xs[", count: levels) + "0" + String(repeating: "]", count: levels)
        // The `if` is a level, and so is the block that gives its value.
        case .callsInIf:
            String(repeating: "f(x: ", count: levels / 2) + "if b { "
                + Shape.calls.expression(levels: levels - levels / 2 - 2) + " } else { 0 }"
                + String(repeating: ")", count: levels / 2)
        // The outermost `if` is a level, and each `if`'s block another.
        case .ifValues:
            String(repeating: "if b { ", count: levels - 1) + "0"
                + String(repeating: " } else { 0 }", count: levels - 1)
        case .elseIfChain, .ifStatements, .loops, .callsInLoops: preconditionFailure("the shape nests as statements")
        }
    }
}

/// What a shape that nests as an expression writes before it.
private let valueBinding = "let value = "

/// The file up to the code that nests, which lies in `main`'s body, so it nests only as deep as it is written.
private let programUpToCode = """
    func f(x: Int) -> Int { x }
    func main() {
        let xs: [1 of UInt] = [0]
        let b = true

    """ + "    "

/// A program whose `main` runs `code`, followed by the declarations in `after`.
private func program(_ code: String, then after: String = "") -> String {
    programUpToCode + code + "\n    if b { print(xs[0]) }\n}\n" + after
}

/// Runs `rayoc` with `arguments` before the path of the file that holds `source`, writing nothing.
private func run(_ arguments: [String], on source: String) -> CompilerResult {
    Compiler.run(arguments + ["main.rayo"], readFile: { $0 == "main.rayo" ? Array(source.utf8) : nil }) { _, _ in
        true
    }
}

/// Each way `rayoc` runs every stage, as the options that ask for it, but for printing the checked program.
private let everyOutputButTheCheckedProgram = [
    ["--check"], ["--emit=ir"], ["--debug", "-o", "main.o"], ["--release", "-o", "main.o"],
]

/// The compiles of code as deep as the limit that the tests run: each shape through every stage, and a sum and
/// parentheses printed as the checked program too. The checked program indents each level, so its text grows with the
/// square of the depth, to hundreds of megabytes for each shape but parentheses: a sum stands for the rest.
private let compilesAtTheLimit = Shape.allCases.flatMap { shape in everyOutputButTheCheckedProgram.map { (shape, $0) } }
    + [(Shape.sum, ["--emit=checked"]), (Shape.parentheses, ["--emit=checked"])]

/// One level more than the limit.
private let pastTheLimit = Parser.nestingLevelLimit + 1

/// Each shape, written a level past the limit, and its code up to the part that passes the limit. That part is, for a
/// sum, the sum itself; for parentheses, what the innermost pair holds; for calls, the innermost argument; and for a
/// shape that nests blocks, the `{` of the block that passes it.
private let codeBeforeTooDeep = [
    (Shape.sum, valueBinding),
    (.parentheses, valueBinding + String(repeating: "(", count: pastTheLimit)),
    (
        .callsInIf,
        valueBinding + String(repeating: "f(x: ", count: pastTheLimit / 2) + "if b { "
            + String(repeating: "f(x: ", count: pastTheLimit - pastTheLimit / 2 - 2),
    ),
    (
        .callsInLoops,
        String(repeating: "while b { ", count: pastTheLimit / 2) + "_ = "
            + String(repeating: "f(x: ", count: pastTheLimit - pastTheLimit / 2),
    ),
    (.ifValues, valueBinding + String(repeating: "if b { ", count: Parser.nestingLevelLimit - 1) + "if b "),
    (.elseIfChain, "if b {}" + String(repeating: " else if b {}", count: Parser.nestingLevelLimit - 1) + " else if b "),
    (.ifStatements, String(repeating: "if b { ", count: Parser.nestingLevelLimit) + "if b "),
    (.loops, String(repeating: "while b { ", count: Parser.nestingLevelLimit) + "while b "),
]

struct NestingDepthTests {
    @Test(arguments: compilesAtTheLimit)
    private func `every stage takes code as deep as the limit`(shape: Shape, arguments: [String]) {
        let result = run(arguments, on: program(shape.code(levels: Parser.nestingLevelLimit)))
        #expect(result.exitCode == 0, "\(result.errors)")
    }

    @Test(arguments: codeBeforeTooDeep)
    private func `code a level past the limit is reported once, at the part that passes it`(
        shape: Shape, codeBefore: String,
    ) {
        let source = program(shape.code(levels: pastTheLimit))
        let diagnostics = run(["--check"], on: source).diagnostics
        #expect(diagnostics.map(\.code) == [.nestingTooDeep(limit: Parser.nestingLevelLimit)])
        #expect(diagnostics.first?.range.start.offset == (programUpToCode + codeBefore).utf8.count)
    }

    @Test func `the error names the limit, which is 10,000 levels`() {
        let diagnostics = run(["--check"], on: program(Shape.loops.code(levels: 10_001))).diagnostics
        #expect(diagnostics.map(\.code.message) == ["the code nests more than 10000 levels deep"])
    }

    @Test(arguments: Shape.allCases, [pastTheLimit, 200_000])
    private func `code past the limit fails alone, and the compile goes on after it`(shape: Shape, levels: Int) {
        let source = program(shape.code(levels: levels), then: "func g() { copy }\n")
        let diagnostics = run(["--check"], on: source).diagnostics
        #expect(diagnostics.map(\.code) == [
            .nestingTooDeep(limit: Parser.nestingLevelLimit), .missingCopiedName(found: .token("}")),
        ])
    }
}
