import Testing
import RayoDiagnostics

/// A body whose errors only the ownership checks, which run after checking, would report: a use of a local that
/// holds no value, and, were that checked no further, a value no code reads.
private let ownershipErrors = """
        let x: Int
        let unread = x
    """

struct ErrorContainmentTests {
    @Test(arguments: [
        // A function that failed to parse, with its name.
        ("func broken( {\n}", [ErrorCode.missingParameterName(found: .token("{"))]),
        // A function whose parameter's type names no type.
        ("func broken(_ n: Nope) {}", [.notAType(name: "Nope")]),
        // A function whose parameter's type, or whose result type, is a struct that can't be laid out.
        ("struct Loop(let next: Loop)\nfunc broken(_ n: Loop) {}", [.containsItself(name: "Loop")]),
        ("struct Loop(let next: Loop)\nfunc broken(_ n: Int) -> Loop { broken(n) }", [.containsItself(name: "Loop")]),
        // A function whose body gives its result type, and fails.
        ("func broken(_ n: Int) { true + 1 }", [
            .integerOperands(op: "+", left: .named("Bool"), right: .named("Int")),
        ]),
    ])
    func `a call to a function whose declaration failed reports nothing more, and taints its caller`(
        declaration: String, expected: [ErrorCode],
    ) {
        let source = "func main() {\n\(ownershipErrors)\n    broken(x)\n}\n" + declaration
        #expect(errors(source) == expected)
    }

    @Test(arguments: [
        // A struct that failed to parse, with its name.
        ("struct Broken(var x Int)", [ErrorCode.unclosedFields(found: .token("Int"))]),
        // A struct whose field's type names no type.
        ("struct Broken(var x: Nope)", [.notAType(name: "Nope")]),
        // A struct that contains itself, and one that contains it.
        ("struct Broken(var inner: Loop)\nstruct Loop(var next: Loop)", [.containsItself(name: "Loop")]),
    ])
    func `a use of a struct whose declaration failed reports nothing more, and taints the body`(
        declaration: String, expected: [ErrorCode],
    ) {
        let source = "func main() {\n\(ownershipErrors)\n    let b: Broken = Broken(x: x)\n    print(b)\n}\n"
            + declaration
        #expect(errors(source) == expected)
    }

    @Test func `no missing 'return' is reported after a statement that failed to parse`() {
        #expect(errors("func main() {}\nfunc f() -> Int {\n    return )\n}") == [
            .missingExpression(found: .token(")")),
        ])
    }

    @Test(arguments: [
        // The second declaration of the name is reported at its name, whichever failed to parse.
        ("struct P(let x Int)\nstruct P(let x: Int)", [ErrorCode.alreadyDeclared(name: "P")], "P"),
        ("struct P(let x: Int)\nstruct P(let x Int)", [.alreadyDeclared(name: "P")], "P"),
        ("struct f(let x Int)\nfunc f() {}", [.alreadyDeclared(name: "f")], "f"),
        ("struct _(let x Int)", [.underscoreDeclared], "_"),
    ])
    func `a struct that failed to parse takes its name, as one that parsed does`(
        source: String, nameErrors: [ErrorCode], covered: String,
    ) {
        let reported = diagnostics("func main() {}\n" + source)
        let nameDiagnostics = reported.filter { $0.code != .unclosedFields(found: .token("Int")) }
        #expect(reported.count == nameDiagnostics.count + 1)
        #expect(nameDiagnostics.map(\.code) == nameErrors)
        #expect(coveredText(nameDiagnostics, in: "func main() {}\n" + source) == [covered])
    }
}
