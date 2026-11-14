import Testing
import RayoCompiler
import RayoDiagnostics

/// Functions that each report an error from one stage that checks a body: a syntax error, a type error, a use of a
/// local that holds no value, and a value no code reads.
private let failingFunctions = """
    func parses() {
        let = 1
    }
    func types() {
        let flag: Bool = 1
    }
    func initializes() {
        let x: Int
        print(x)
    }
    func reads() {
        let unread = 1
    }
    """

/// The errors `failingFunctions` report, in source order.
private let failingFunctionsErrors: [ErrorCode] = [
    .missingBindingName(found: .token("=")), .typeMismatch(expected: .named("Bool"), found: .named("Int")),
    .usedUninitialized(name: "x"), .unreadValue(name: "unread"),
]

/// A body that would report an error at each check after checking: a use of a local that holds no value, and, were
/// that checked no further, a value no code reads.
private let ownershipErrors = """
        let x: Int
        let unread = x
    """

/// The errors `rayoc -o` reports for `source`, and whether it wrote the object file.
private func objectCodeErrors(_ source: String) -> (errors: [ErrorCode], wrote: Bool) {
    var wrote = false
    let result = Compiler.run(["-o", "a.o", "a.rayo"], readFile: { _ in Array(source.utf8) }) { _, _ in
        wrote = true
        return true
    }
    return (result.diagnostics.map(\.code), wrote)
}

struct ErrorContainmentTests {
    @Test func `an error in one function stops no stage from checking the others`() {
        #expect(errors("func main() {}\n" + failingFunctions) == failingFunctionsErrors)
    }

    @Test func `a compile with any error writes nothing, and reports every stage's errors in source order`() {
        let compiled = objectCodeErrors("func main() {}\n" + failingFunctions)
        #expect(compiled.errors == failingFunctionsErrors)
        #expect(!compiled.wrote)
    }

    @Test(arguments: [
        ("func main() {\n    let = 1\n\(ownershipErrors)\n}", [ErrorCode.missingBindingName(found: .token("="))]),
        ("func main() {\n    print(1) 2\n\(ownershipErrors)\n}", [.unendedStatement(found: .token("2"))]),
        ("func main() {\n    let flag: Bool = 1\n\(ownershipErrors)\n}", [
            .typeMismatch(expected: .named("Bool"), found: .named("Int")),
        ]),
    ])
    func `a function whose body fails to parse or to check is checked no further`(
        source: String, expected: [ErrorCode],
    ) {
        #expect(errors(source) == expected)
    }

    @Test(arguments: [
        // A function that failed to parse, with its name.
        ("func broken( {\n}", [ErrorCode.missingParameterName(found: .token("{"))]),
        // A function whose parameter's type names no type.
        ("func broken(_ n: Nope) {}", [.notAType(name: "Nope")]),
        // A function whose body gives its result type, and fails.
        ("func broken(_ n: Int) { true + 1 }", [
            .operandTypes(op: "+", needs: .named("Int"), left: .named("Bool"), right: .named("Int")),
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

    @Test func `a function that calls one whose body is tainted is checked as any other`() {
        let source = "func main() {\n\(ownershipErrors)\n    tainted()\n}\nfunc tainted() {\n    let = 1\n}"
        #expect(errors(source) == [.usedUninitialized(name: "x"), .missingBindingName(found: .token("="))])
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

    @Test(arguments: [
        // A function that failed before its name, or that is named `main`, may have been `main`.
        ("func (", [ErrorCode.missingFunctionName(found: .token("("))]),
        ("func main( {\n}", [.missingParameterName(found: .token("{"))]),
        // Any other declaration that failed can't have been. The missing `main` is reported at the file's start.
        ("func helper( {\n}", [.noMain, .missingParameterName(found: .token("{"))]),
        ("struct main(", [.noMain, .missingFieldKind(found: .endOfFile)]),
        // A missing `main` is reported alongside the other errors of a file that has no failed declaration.
        ("func helper() {\n    let = 1\n}", [.noMain, .missingBindingName(found: .token("="))]),
    ])
    func `a missing 'main' is reported unless a declaration that failed may have been it`(
        source: String, expected: [ErrorCode],
    ) {
        #expect(objectCodeErrors(source).errors == expected)
    }

    @Test func `a file that isn't UTF-8 is checked no further`() {
        let source = Array("func f() {}\n".utf8) + [0xFF]
        let result = Compiler.run(["-o", "a.o", "a.rayo"], readFile: { _ in source }) { _, _ in true }
        #expect(result.diagnostics.map(\.code) == [.notUTF8])
    }
}
