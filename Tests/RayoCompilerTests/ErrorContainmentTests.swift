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
        let unread = copy x
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

    @Test func `a declaration whose header fails to parse reports its syntax errors, and is checked no further`() {
        let source = """
            func main() {}
            func f(x) {
                let = 1
                let flag: Bool = 1
            }
            struct S(a: Int, var b: Nope, var b: Int)
            """
        #expect(errors(source) == [
            .missingParameterType(found: .token(")")), .missingBindingName(found: .token("=")),
            .missingFieldKind(found: .token("a")),
        ])
    }

    @Test func `an unused value leaves its body's meaning whole, so the ownership checks still run on it`() {
        let source = """
            func g() -> Int { return 1 }
            func main() {
                g()
                let x = 5
                let y = consume x
                print(x)
                print(y)
            }
            """
        #expect(errors(source) == [.unusedValue(type: "Int"), .usedAfterMove(name: "x")])
    }

    @Test(arguments: [
        ("let a = [1, 2, 3]\n    _ = copy a[3]", ErrorCode.indexOutOfRange(index: 3, type: "[3 of Int]")),
        ("var a = [1, 2, 3]\n    a[3] = 4\n    _ = a", .indexOutOfRange(index: 3, type: "[3 of Int]")),
        ("let n: Int = 9223372036854775808\n    _ = n", .literalDoesntFit(type: "Int")),
        ("let u: UInt = -1\n    _ = u", .literalDoesntFit(type: "UInt")),
        ("let n = 9223372036854775808\n    _ = n", .literalDoesntFit(type: "Int")),
        ("let a = [1, 2, 3]\n    _ = copy a[-1]", .literalDoesntFit(type: "UInt")),
        ("var a = [1, 2, 3]\n    a[-1] = 4\n    _ = a", .literalDoesntFit(type: "UInt")),
        // An unused local is read where it stands, never moved, so a later use of it reports nothing more.
        ("let a = [1, 2, 3]\n    a\n    _ = a", .unusedValue(type: "[3 of Int]")),
    ])
    func `an error that leaves a body's meaning whole lets the ownership checks run on it`(
        body: String, error: ErrorCode,
    ) {
        #expect(errors("func main() {\n    \(body)\n\(ownershipErrors)\n}") == [error, .usedUninitialized(name: "x")])
    }

    @Test(arguments: [
        ("let a = 3 $ 4", [ErrorCode.unexpectedCharacter(character: "$")]),
        ("let a: Int = )", [.missingExpression(found: .token(")"))]),
        ("let b = 1, a = 2 3", [.unendedStatement(found: .token("3"))]),
        ("let a: [9223372036854775807 of Int] = .init(repeating: 0)", [.arrayTooLarge]),
        ("let a: Nope = .init(repeating: 0)", [.notAType(name: "Nope")]),
    ])
    func `a local whose declaration fails reports nothing more where it is used`(
        declaration: String, expected: [ErrorCode],
    ) {
        #expect(errors("func main() {\n    \(declaration)\n    print(a)\n}") == expected)
    }

    // Nothing written says whether the call copies the place or moves it, so the call takes neither.
    @Test func `a '&' given to a parameter that owns its argument reports nothing more of the place`() {
        let source = """
            func main() {
                let s = Stats(hp: 1)
                let e = Enemy(stats: &s)
                print(s.hp + e.stats.hp)
            }
            struct Enemy(var stats: Stats)
            struct Stats(var hp: Int)
            """
        #expect(errors(source) == [.referenceToOwnedParameter(name: "Enemy", type: "Stats")])
    }

    @Test func `a function that calls one whose body is tainted is checked as any other`() {
        let source = "func main() {\n\(ownershipErrors)\n    tainted()\n}\nfunc tainted() {\n    let = 1\n}"
        #expect(errors(source) == [.usedUninitialized(name: "x"), .missingBindingName(found: .token("="))])
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
