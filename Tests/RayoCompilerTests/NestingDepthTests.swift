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

/// How many levels deep struct bodies may nest.
private let structBodyLimit = CappedPart.structBody.limit

/// The text that opens a struct and its body.
private let structOpening = "struct S { "

/// A file of structs whose bodies nest `levels` levels deep, each the only member of the one around it, then `main`
/// and the declarations in `after`.
private func nestedStructs(levels: Int, then after: String = "") -> String {
    let structs = String(repeating: structOpening, count: levels) + String(repeating: "}", count: levels)
    return structs + "\nfunc main() {}\n" + after
}

struct StructBodyNestingTests {
    @Test func `struct bodies as deep as the limit report only that a struct's body can't hold declarations`() {
        let diagnostics = run(["--check"], on: nestedStructs(levels: structBodyLimit)).diagnostics
        #expect(diagnostics.map(\.code) == [.unsupportedMember])
    }

    @Test func `a struct body a level past the limit is reported once, at its brace`() {
        let diagnostics = run(["--check"], on: nestedStructs(levels: structBodyLimit + 1)).diagnostics
        let codeBefore = String(repeating: structOpening, count: structBodyLimit) + "struct S "
        #expect(diagnostics.map(\.code) == [.unsupportedMember, .nestingTooDeep(limit: structBodyLimit)])
        #expect(diagnostics.last?.range.start.offset == codeBefore.utf8.count)
    }

    @Test func `the error names the limit, which is 64 levels`() {
        let diagnostics = run(["--check"], on: nestedStructs(levels: 65)).diagnostics
        #expect(diagnostics.last?.code.message == "the code nests more than 64 levels deep")
    }

    @Test(arguments: [structBodyLimit + 1, 1_000_000])
    private func `struct bodies past the limit fail alone, and the compile goes on after them`(levels: Int) {
        let diagnostics = run(["--check"], on: nestedStructs(levels: levels, then: "func g() { copy }\n")).diagnostics
        #expect(diagnostics.map(\.code) == [
            .unsupportedMember, .nestingTooDeep(limit: structBodyLimit), .missingCopiedName(found: .token("}")),
        ])
    }
}

/// How many levels deep array types may nest.
private let arrayTypeLimit = CappedPart.arrayType.limit

/// The text that opens an array type of one element.
private let arrayTypeOpening = "[1 of "

/// `[1 of [1 of … Int …]]`, array types nested `levels` levels deep around `Int`.
private func nestedArrayType(levels: Int) -> String {
    String(repeating: arrayTypeOpening, count: levels) + "Int" + String(repeating: "]", count: levels)
}

/// The file up to the type of `main`'s local.
private let programUpToArrayType = "func main() {\n    let xs: "

/// `[[…leaf…]]`, array literals nested `levels` levels deep around `leaf`.
private func nestedArrayLiteral(levels: Int, around leaf: String = "0") -> String {
    String(repeating: "[", count: levels) + leaf + String(repeating: "]", count: levels)
}

/// A program whose `main` binds a local whose type nests array types `levels` levels deep, followed by the
/// declarations in `after`. The local is consumed whole, since indexing down to its Int would nest as deep as its type.
private func nestedArray(levels: Int, then after: String = "") -> String {
    let value = nestedArrayLiteral(levels: levels)
    return programUpToArrayType + nestedArrayType(levels: levels) + " = " + value + "\n    _ = consume xs\n}\n" + after
}

/// Each place a type is written, as the code before a type there and the code after it to the end of the file.
private let typePlaces = [
    (programUpToArrayType, " = 0\n}\n"),
    ("func f(xs: ", ") {}\nfunc main() {}\n"),
    ("func f() -> ", " {}\nfunc main() {}\n"),
    ("struct S(var xs: ", ")\nfunc main() {}\n"),
]

struct ArrayTypeNestingTests {
    @Test(arguments: everyOutputButTheCheckedProgram + [["--emit=checked"]])
    private func `every stage takes an array type as deep as the limit`(arguments: [String]) {
        let result = run(arguments, on: nestedArray(levels: arrayTypeLimit))
        #expect(result.exitCode == 0, "\(result.errors)")
    }

    @Test(arguments: typePlaces)
    private func `an array type a level past the limit is reported once, at its bracket, wherever it is written`(
        before: String, after: String,
    ) {
        let diagnostics = run(["--check"], on: before + nestedArrayType(levels: arrayTypeLimit + 1) + after).diagnostics
        let codeBefore = before + String(repeating: arrayTypeOpening, count: arrayTypeLimit)
        #expect(diagnostics.map(\.code) == [.nestingTooDeep(limit: arrayTypeLimit)])
        #expect(diagnostics.first?.range.start.offset == codeBefore.utf8.count)
    }

    @Test func `the error names the limit, which is 64 levels`() {
        let diagnostics = run(["--check"], on: nestedArray(levels: 65)).diagnostics
        #expect(diagnostics.map(\.code.message) == ["the code nests more than 64 levels deep"])
    }

    @Test(arguments: [arrayTypeLimit + 1, 1_000_000])
    private func `an array type past the limit fails alone, and the compile goes on after it`(levels: Int) {
        let diagnostics = run(["--check"], on: nestedArray(levels: levels, then: "func g() { copy }\n")).diagnostics
        #expect(diagnostics.map(\.code) == [
            .nestingTooDeep(limit: arrayTypeLimit), .missingCopiedName(found: .token("}")),
        ])
    }
}

/// The file up to the statements of `main`.
private let programUpToMainBody = "func main() {\n"

/// The statement that binds `xs`, with no type written, up to its value.
private let untypedBinding = "    let xs = "

/// The statement that binds the condition of an `if`.
private let conditionBinding = "    let b = true\n"

/// A program whose `main` runs `statements`, then binds `xs` to `value` with no type written and consumes it whole,
/// followed by the declarations in `declarations`.
private func programBinding(_ value: String, after statements: String = "", then declarations: String = "") -> String {
    programUpToMainBody + statements + untypedBinding + value + "\n    _ = consume xs\n}\n" + declarations
}

/// A literal as deep as the limit, around an Int.
private let literalAtTheLimit = nestedArrayLiteral(levels: arrayTypeLimit)

/// A literal as deep as the limit, around an empty literal.
private let emptyLiteralAtTheLimit = nestedArrayLiteral(levels: arrayTypeLimit - 1, around: "[]")

/// Values of `xs` whose outermost literal would take an array type a level past the limit, each after the statements
/// `main` runs before it. The literal holds a literal, around an Int or an empty one; a local whose type is as deep as
/// the limit; or an `if` whose branches are such literals.
private let literalsPastTheLimit = [
    ("", "[" + literalAtTheLimit + "]"),
    ("", "[" + emptyLiteralAtTheLimit + "]"),
    ("    let inner = " + literalAtTheLimit + "\n", "[inner]"),
    (conditionBinding, "[if b { " + literalAtTheLimit + " } else { " + literalAtTheLimit + " }]"),
    (conditionBinding, "[if b { " + emptyLiteralAtTheLimit + " } else { [] }]"),
]

struct ArrayLiteralNestingTests {
    @Test(arguments: everyOutputButTheCheckedProgram + [["--emit=checked"]])
    private func `every stage takes a literal as deep as the limit with no type written`(arguments: [String]) {
        let result = run(arguments, on: programBinding(literalAtTheLimit))
        #expect(result.exitCode == 0, "\(result.errors)")
    }

    @Test(arguments: everyOutputButTheCheckedProgram)
    private func `a literal takes a parameter's type as deep as the limit`(arguments: [String]) {
        let function = "func f(xs: \(nestedArrayType(levels: arrayTypeLimit))) { _ = consume xs }\n"
        let source = function + "func main() {\n    f(xs: \(literalAtTheLimit))\n}\n"
        let result = run(arguments, on: source)
        #expect(result.exitCode == 0, "\(result.errors)")
    }

    @Test(arguments: everyOutputButTheCheckedProgram)
    private func `a literal no element gives a type takes an annotation's type as deep as the limit`(
        arguments: [String],
    ) {
        let type = String(repeating: arrayTypeOpening, count: arrayTypeLimit - 1) + "[0 of Int]"
            + String(repeating: "]", count: arrayTypeLimit - 1)
        let source = programUpToArrayType + type + " = " + emptyLiteralAtTheLimit + "\n    _ = consume xs\n}\n"
        let result = run(arguments, on: source)
        #expect(result.exitCode == 0, "\(result.errors)")
    }

    @Test(arguments: literalsPastTheLimit)
    private func `a literal whose type would nest past the limit is reported once, at that literal`(
        statements: String, value: String,
    ) {
        let diagnostics = run(["--check"], on: programBinding(value, after: statements)).diagnostics
        let tooDeep = diagnostics.filter { $0.code == .nestingTooDeep(limit: arrayTypeLimit) }
        #expect(tooDeep.count == 1)
        #expect(tooDeep.first?.range.start.offset == (programUpToMainBody + statements + untypedBinding).utf8.count)
    }

    @Test func `a literal past the limit still reports its elements' own errors`() {
        let value = nestedArrayLiteral(levels: arrayTypeLimit + 1, around: "9223372036854775808")
        let diagnostics = run(["--check"], on: programBinding(value)).diagnostics
        let codeBeforeInt = programUpToMainBody + untypedBinding + String(repeating: "[", count: arrayTypeLimit + 1)
        #expect(diagnostics.map(\.code) == [
            .nestingTooDeep(limit: arrayTypeLimit), .literalDoesntFit(type: "Int"),
        ])
        #expect(diagnostics.last?.range.start.offset == codeBeforeInt.utf8.count)
    }

    @Test(arguments: [arrayTypeLimit + 1, Parser.nestingLevelLimit])
    private func `a literal past the limit fails alone, and the compile goes on after it`(levels: Int) {
        let source = programBinding(nestedArrayLiteral(levels: levels), then: "func g() { _ = [] }\n")
        let diagnostics = run(["--check"], on: source).diagnostics
        let codeBefore = programUpToMainBody + untypedBinding
            + String(repeating: "[", count: levels - arrayTypeLimit - 1)
        #expect(diagnostics.map(\.code) == [.nestingTooDeep(limit: arrayTypeLimit), .emptyArrayLiteral])
        #expect(diagnostics.first?.range.start.offset == codeBefore.utf8.count)
    }
}
