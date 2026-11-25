import Testing
import RayoCompiler
import RayoDiagnostics
import RayoSyntax

/// Shapes an expression nests in, each written `levels` levels deep.
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
    /// `f(x: …if true { f(x: …1…) } else { 0 }…)`: calls around an `if`, and calls in the block whose value it
    /// gives, each about half the levels.
    case callsInIf

    func expression(levels: Int) -> String {
        switch self {
        case .sum: "0" + String(repeating: " + 1", count: levels)
        case .parentheses: String(repeating: "(", count: levels) + "1" + String(repeating: ")", count: levels)
        case .negations: String(repeating: "!", count: levels) + "true"
        case .calls: String(repeating: "f(x: ", count: levels) + "1" + String(repeating: ")", count: levels)
        case .elements: String(repeating: "xs[", count: levels) + "0" + String(repeating: "]", count: levels)
        case .callsInIf:
            String(repeating: "f(x: ", count: levels / 2) + "if true { "
                + Shape.calls.expression(levels: levels - levels / 2 - 1) + " } else { 0 }"
                + String(repeating: ")", count: levels / 2)
        }
    }
}

/// The file up to the expression, which `main` binds to a local, so the expression nests only as deep as it is
/// written.
private let printPrefix = """
    func f(x: Int) -> Int { x }
    func main() {
        let xs: [1 of UInt] = [0]

    """ + "    let value = "

/// A program whose `main` prints `expression`, followed by the declarations in `after`.
private func printing(_ expression: String, then after: String = "") -> String {
    printPrefix + expression + "\n    print(value)\n    print(xs[0])\n}\n" + after
}

/// Runs `rayoc` with `arguments` before the path of the file that holds `source`, writing nothing.
private func run(_ arguments: [String], on source: String) -> CompilerResult {
    Compiler.run(arguments + ["main.rayo"], readFile: { $0 == "main.rayo" ? Array(source.utf8) : nil }) { _, _ in
        true
    }
}

/// Each way `rayoc` runs every stage, as the options that ask for it.
private let everyOutput = [
    ["--check"], ["--emit=checked"], ["--emit=ir"], ["--debug", "-o", "main.o"], ["--release", "-o", "main.o"],
]

/// The compiles of an expression as deep as the limit that the tests run: a sum and parentheses in every output,
/// calls, whose levels take the most stack of any shape, through every stage of a compile to object code, and calls
/// that go on inside an `if`.
private let compilesAtTheLimit = everyOutput.map { (Shape.sum, $0) } + everyOutput.map { (Shape.parentheses, $0) }
    + [(Shape.calls, ["--debug", "-o", "main.o"]), (Shape.callsInIf, ["--check"])]

struct ExpressionDepthTests {
    /// A deep sum or call takes a debug `rayoc` seconds to check, so these compiles run one at a time, which leaves
    /// the processor's other cores to the other tests.
    @Test(.serialized, arguments: compilesAtTheLimit)
    private func `every stage takes an expression as deep as the limit, from a client whose stack is small`(
        shape: Shape, arguments: [String],
    ) async {
        let source = printing(shape.expression(levels: Parser.expressionLevelLimit))
        let result = await onNewThread(stackSize: smallStackSize) { run(arguments, on: source) }
        #expect(result.exitCode == 0, "\(result.errors)")
    }

    /// Each shape, and how many bytes into it the part that passes the limit starts: for a sum, the sum itself, and
    /// for parentheses, what the innermost pair holds.
    @Test(arguments: [(Shape.sum, 0), (.parentheses, Parser.expressionLevelLimit + 1)])
    private func `an expression a level past the limit is reported once, at the part that passes it`(
        shape: Shape, startOfTooDeep: Int,
    ) {
        let source = printing(shape.expression(levels: Parser.expressionLevelLimit + 1))
        let diagnostics = run(["--check"], on: source).diagnostics
        #expect(diagnostics.map(\.code) == [.expressionTooDeep(limit: Parser.expressionLevelLimit)])
        #expect(diagnostics.first?.range.start.offset == printPrefix.utf8.count + startOfTooDeep)
    }

    @Test func `the error names the limit, which is 10,000 levels`() {
        let diagnostics = run(["--check"], on: printing(Shape.sum.expression(levels: 10_001))).diagnostics
        #expect(diagnostics.map(\.code.message) == ["the expression nests more than 10000 levels deep"])
    }

    @Test(arguments: Shape.allCases, [Parser.expressionLevelLimit + 1, 200_000])
    private func `an expression past the limit fails alone, and the compile goes on after it`(
        shape: Shape, levels: Int,
    ) {
        let source = printing(shape.expression(levels: levels), then: "func g() { copy }\n")
        let diagnostics = run(["--check"], on: source).diagnostics
        #expect(diagnostics.map(\.code) == [
            .expressionTooDeep(limit: Parser.expressionLevelLimit), .missingCopiedName(found: .token("}")),
        ])
    }
}
