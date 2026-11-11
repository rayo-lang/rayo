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
        #expect(reported.map(\.code) == [.unusedValue(type: type)])
        #expect(coveredText(reported, in: source) == [expression])
    }

    @Test("the single expression of a body whose result type is Void must be Void", arguments: [
        ("func main() { 3 }", "3", "Int"), ("func main() { g() }", "g()", "Int"),
        ("func main() {}\nfunc f() -> Void { true }", "true", "Bool"),
        ("func main() {}\nfunc f() -> () { 1 + 2 }", "1 + 2", "Int"),
    ])
    func voidBody(declarations: String, expression: String, type: String) {
        let source = declarations + "\nfunc g() -> Int { 3 }"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.unusedValue(type: type)])
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

    @Test("a dropped value is checked, a local's value is moved, and '_' declares nothing", arguments: [
        ("let x = 1\n_ = x", [ErrorCode]()),
        ("_ = nope", [.notDeclared(name: "nope")]),
        ("_ = _", [.underscoreValue]),
        ("_ == 1", [.underscoreValue]),
        ("(_) = 1", [.assignToNonLocal]),
        ("_ = 1\nprint(_)", [.underscoreValue]),
    ])
    func droppedChecked(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() {\n\(body)\n}") == expected)
    }
}
