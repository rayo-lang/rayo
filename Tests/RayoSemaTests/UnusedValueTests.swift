import Testing
import RayoDiagnostics

struct UnusedValueTests {
    @Test("an expression statement whose value isn't Void is an error, which covers the expression", arguments: [
        ("g()", "g()", "Int"), ("1 + 2", "1 + 2", "Int"), ("true", "true", "Bool"),
        ("let x = 1\nx", "x", "Int"), ("let x = 1\ncopy x", "copy x", "Int"),
        ("if true { 1 < 2 }", "1 < 2", "Bool"), ("while true {\n-2\nbreak\n}", "-2", "Int"),
    ])
    func unusedStatement(body: String, expression: String, type: String) {
        let source = "func main() {\n\(body)\n}\nfunc g() -> Int { 3 }"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.unusedValue(type: .named(type), drop: .bare)])
        #expect(coveredText(reported, in: source) == [expression])
    }

    // `_ =` takes a bare place only where its type is implicitly copyable, so the error names how to drop any other:
    // `consume` where the code may move out of the place, and `copy` where it can't.
    @Test(arguments: [
        ("e", "the Enemy value isn't used; write '_ = consume' before it to drop it"),
        ("e.stats", "the Stats value isn't used; write '_ = consume' before it to drop it"),
        ("a", "the [2 of Int] value isn't used; write '_ = consume' before it to drop it"),
        ("g[0]", "the Enemy value isn't used; write '_ = copy' before it to drop it"),
        ("r", "the Enemy value isn't used; write '_ = copy' before it to drop it"),
        ("e.stats.hp", "the Int value isn't used; write '_ =' before it to drop it"),
        ("makeEnemy()", "the Enemy value isn't used; write '_ =' before it to drop it"),
        ("makeEnemy().stats", "the Stats value isn't used; write '_ =' before it to drop it"),
    ])
    func `an unused value names how to drop it, by its type and by whether the code may move out of its place`(
        expression: String, message: String,
    ) {
        let body = """
            let e = makeEnemy()
            let a = [1, 2]
            let g = [makeEnemy(), makeEnemy()]
            ref let r = &e
            \(expression)
            """
        let declarations = """
            struct Enemy(var stats: Stats)
            struct Stats(var hp: Int)
            func makeEnemy() -> Enemy { Enemy(stats: Stats(hp: 1)) }
            """
        #expect(errorLines(inMain: body, beside: declarations) == ["6:1: error[E0235]: \(message)"])
    }

    // A borrowing parameter's value is its caller's, so the function can't move it out.
    @Test func `an unused borrowing parameter of a struct says to drop a copy`() {
        let source = "func main() {}\nfunc f(_ e: &Enemy) -> Void {\n    e\n}\nstruct Enemy(var hp: Int)"
        #expect(diagnostics(source).map(\.description) == [
            "3:5: error[E0235]: the Enemy value isn't used; write '_ = copy' before it to drop it",
        ])
    }

    @Test("the single expression of a body whose result type is Void must be Void", arguments: [
        ("func main() { 3 }", "3", "Int"), ("func main() { g() }", "g()", "Int"),
        ("func main() {}\nfunc f() -> Void { true }", "true", "Bool"),
        ("func main() {}\nfunc f() -> () { 1 + 2 }", "1 + 2", "Int"),
    ])
    func voidBody(declarations: String, expression: String, type: String) {
        let source = declarations + "\nfunc g() -> Int { 3 }"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.unusedValue(type: .named(type), drop: .bare)])
        #expect(coveredText(reported, in: source) == [expression])
    }

    @Test("a declaration that binds no name is an error, which covers the '_'", arguments: [
        "let _ = 1", "var _ = 1", "let _: Int = 1", "var _: Int = 1",
    ])
    func declaredUnderscore(body: String) {
        #expect(codesAndCoverage(inMain: body) == ([.underscoreDeclared], ["_"]))
    }

    @Test("the value of a declaration that binds no name is still checked, and '_' declares nothing", arguments: [
        ("let _ = nope", [ErrorCode.underscoreDeclared, .notDeclared(name: "nope")]),
        ("let _: Bool = 1", [.underscoreDeclared, .typeMismatch(expected: "Bool", found: "Int")]),
        ("var _: Int8 = 1", [.underscoreDeclared, .notAType(name: "Int8")]),
        ("let _ = 1\nlet _ = 2", [.underscoreDeclared, .underscoreDeclared]),
        ("let _ = 1\nprint(_)", [.underscoreDeclared, .underscoreValue]),
    ])
    func declaredUnderscoreChecked(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() {\n\(body)\n}") == expected)
    }

    @Test("a dropped value is checked, and '_' declares nothing", arguments: [
        ("_ = nope", [ErrorCode.notDeclared(name: "nope")]),
        ("_ = _", [.underscoreValue]),
        ("_ == 1", [.underscoreValue]),
        ("(_) = 1", [.assignToUnderscore]),
        ("_ = 1\nprint(_)", [.underscoreValue]),
    ])
    func droppedChecked(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() {\n\(body)\n}") == expected)
    }
}
