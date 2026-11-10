import Testing
import RayoDiagnostics
import RayoDriver

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

    @Test("'_ =' and 'let _ =' drop a value on purpose, which is still computed")
    func dropped() {
        let source = """
            func main() {
                _ = say(1)
                let _ = say(2)
                var _: Int = say(3)
                _ = print(4)
                let x = 5
                _ = copy x
            }
            func say(_ x: Int) -> Int {
                print(x)
                return copy x
            }
            """
        #expect(run(source) == Driver.Result(exitCode: 0, output: "1\n2\n3\n4\n", errors: ""))
    }

    @Test("a dropped value is checked, a local's value is taken with 'copy', and '_' declares nothing", arguments: [
        ("let x = 1\n_ = x", [ErrorCode.takenWithoutCopy(name: "x")]),
        ("let x = 1\nlet _ = x", [.takenWithoutCopy(name: "x")]),
        ("let _: Bool = 1", [.typeMismatch(expected: "Bool", found: "Int")]),
        ("let _: Int8 = 1", [.notAType(name: "Int8")]),
        ("_ = nope", [.notDeclared(name: "nope")]),
        ("_ = _", [.underscoreValue]),
        ("(_) = 1", [.assignToNonLocal]),
        ("let _ = 1\nprint(_)", [.underscoreValue]),
        ("let _ = 1\nlet _ = nope\nvar _ = 2", [.notDeclared(name: "nope")]),
    ])
    func droppedChecked(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() {\n\(body)\n}") == expected)
    }
}
