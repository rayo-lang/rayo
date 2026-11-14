import Testing
import RayoDiagnostics

/// Declarations that the bodies below use: a struct with an Int field, overloads that a literal tells apart, and a
/// function that returns an Int.
private let declarations = """
    struct Hit(var damage: Int)
    func f(_ a: Int, _ b: Int) {}
    func f(_ a: Int, _ b: Bool) {}
    func g(_ s: Hit) {}
    func g(_ n: Int) {}
    func h(_ b: Bool) {}
    func h(_ s: Hit) {}
    func double(_ n: Int) -> Int { 2 * copy n }
    """

/// The errors that `body`, as `main`'s body beside `declarations`, reports, and the text each covers.
private func reported(inMain body: String) -> (codes: [ErrorCode], covered: [String]) {
    let source = "func main() {\n\(body)\n}\n\(declarations)"
    let found = diagnostics(source)
    return (found.map(\.code), coveredText(found, in: source))
}

struct LiteralTypeTests {
    @Test(arguments: [
        "let a: Int = 2 * 3\nprint(a)",
        "var a: Int\na = -1 + 2\nprint(a)",
        "var a = 1\na += 3 * 4\nprint(a)",
        "_ = Hit(damage: 1 + 1)",
        "_ = double(-1)",
        "if 1 < 2 { }",
        "print(1 == 2)",
        "let a = 1\nprint(a + 1)",
        "let a = 1\nprint(2 * 3 - a)",
        "print(if true { 1 } else { 2 })",
        "print(2 * -3)",
    ])
    func `a literal takes its type from its position, from the other operand, or else its default`(body: String) {
        #expect(reported(inMain: body).codes == [])
    }

    @Test(arguments: [
        "f(1, 2)",
        "let a = 1\nf(a, 2)",
        "g(1)",
        "g(2 * 3)",
    ])
    func `an overload drops out where an untyped argument doesn't fit its parameter`(body: String) {
        #expect(reported(inMain: body).codes == [])
    }

    @Test(arguments: [
        ("let a: Bool = 9223372036854775808", "9223372036854775808"),
        ("var a = 1\na += 9223372036854775808", "9223372036854775808"),
        ("print(1 + 9223372036854775808)", "9223372036854775808"),
        ("print(-(9223372036854775808) * 2)", "(9223372036854775808)"),
        ("h(9223372036854775808)", "9223372036854775808"),
        ("f(1, 9223372036854775808)", "9223372036854775808"),
    ])
    func `a literal that its settled type can't hold is reported, and the error covers the literal`(
        body: String, literal: String,
    ) {
        let (codes, covered) = reported(inMain: body)
        #expect(codes == [.literalDoesntFit(type: "Int")])
        #expect(covered == [literal])
    }

    @Test(arguments: [
        ("print(9223372036854775808 + nope)", [ErrorCode.literalDoesntFit(type: "Int"), .notDeclared(name: "nope")]),
        ("print(nope + 9223372036854775808)", [.notDeclared(name: "nope"), .literalDoesntFit(type: "Int")]),
        ("f(9223372036854775808, nope)", [.literalDoesntFit(type: "Int"), .notDeclared(name: "nope")]),
    ])
    func `a literal its default type can't hold is reported beside an operand or argument that fails`(
        body: String, expected: [ErrorCode],
    ) {
        #expect(reported(inMain: body).codes == expected)
    }

    @Test func `a literal its default type can't hold is reported in a call that two overloads fit`() {
        let source = "func main() { k(9223372036854775808) }\nfunc k(_ a: Int) {}\nfunc k(_ a: Nope) {}"
        #expect(errors(source) == [.literalDoesntFit(type: "Int"), .notAType(name: "Nope")])
    }

    @Test(arguments: [
        ("let a: Bool = 2 * 3", ErrorCode.typeMismatch(expected: "Bool", found: "Int"), "2 * 3"),
        ("var a = true\na += 1", .integerOperands(op: "+=", left: "Bool", right: "Int"), "a += 1"),
        ("let a = true == 1", .operandsDiffer(op: "==", left: "Bool", right: "Int"), "true == 1"),
        ("let a = 1 && 2", .operandTypes(op: "&&", needs: "Bool", left: "Int", right: "Int"), "1 && 2"),
        ("h(1)", .noMatchingFunction(name: "h", arguments: "Int"), "h(1)"),
    ])
    func `a literal that fits no type its position offers takes its default, which the position then reports`(
        body: String, expected: ErrorCode, covered: String,
    ) {
        let (codes, coveredText) = reported(inMain: body)
        #expect(codes == [expected])
        #expect(coveredText == [covered])
    }
}
