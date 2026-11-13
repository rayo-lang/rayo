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
        #expect(reported.map(\.code) == [.unusedValue(type: .named(type))])
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
        #expect(reported.map(\.code) == [.unusedValue(type: .named(type))])
        #expect(coveredText(reported, in: source) == [expression])
    }

    @Test(arguments: [
        ("let x = g()", ["2:5: error[E0308]: the value assigned to 'x' is never read"]),
        ("var y = g()\ny = g()\nprint(y)", ["2:5: error[E0308]: the value assigned to 'y' is never read"]),
        ("var y = g()\nprint(y)\ny = g()", ["4:1: error[E0308]: the value assigned to 'y' is never read"]),
        ("var n = g()\nprint(n)\nn += 1", ["4:1: error[E0308]: the value assigned to 'n' is never read"]),
        ("let k: Int\nif g() > 0 { k = 1 } else { k = 2 }", [
            "3:14: error[E0308]: the value assigned to 'k' is never read",
            "3:29: error[E0308]: the value assigned to 'k' is never read",
        ]),
        ("var x = 1\nwhile true {\nx = 2\n}", [
            "2:5: error[E0308]: the value assigned to 'x' is never read",
            "4:1: error[E0308]: the value assigned to 'x' is never read",
        ]),
    ])
    func `a value that no code reads is an error at the local it is assigned to`(body: String, expected: [String]) {
        #expect(diagnostics("func main() {\n\(body)\n}\nfunc g() -> Int { 3 }").map(\.description) == expected)
    }

    @Test(arguments: [
        "let x = g()\n_ = x",
        "let x = g()\nlet y = x\nprint(y)",
        "var y = g()\nif g() > 0 { print(y) }\ny = g()\nprint(y)",
        "var i = 0\nwhile i < 3 { i += 1 }",
    ])
    func `a value that code reads on some path is used, whether it reads, moves or drops it`(body: String) {
        #expect(errors("func main() {\n\(body)\n}\nfunc g() -> Int { 3 }") == [])
    }

    @Test("a local given no value, a borrowed parameter, and code that no path reaches leave no value unread",
          arguments: [
        "func main() {\nvar x: Int\n}", "func main() {}\nfunc f(_ a: Int) {}", "func main() {\nreturn\nlet x = 1\n}",
    ])
    func nothingUnread(source: String) {
        #expect(errors(source) == [])
    }

    @Test func `a local's other errors are reported in place of its values that no code reads`() {
        #expect(errors("func main() {\nlet k = 1\nk = 2\n}") == [.letAssignedTwice(name: "k")])
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
