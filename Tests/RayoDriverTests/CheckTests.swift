import Testing
import RayoDiagnostics
import RayoDriver

/// The errors `rayoc check` reports for `source`, saved as `main.rayo`.
func errors(_ source: String) -> [ErrorCode] {
    let result = Driver.run(["check", "main.rayo"]) { $0 == "main.rayo" ? Array(source.utf8) : nil }
    #expect(result.exitCode == (result.diagnostics.isEmpty ? 0 : 1))
    #expect(result.output == "")
    return result.diagnostics.map(\.code)
}

struct ProgramTests {
    @Test("a program that checks reports nothing", arguments: [
        "func main() { print(-9223372036854775808) }",
        "func main() -> Void {}",
        "func main() -> () {}",
    ])
    func clean(source: String) {
        #expect(errors(source) == [])
    }

    @Test("a program needs a 'main' that returns Void", arguments: [
        ("", ErrorCode.noMain),
        ("func main() -> Int { 0 }", .mainResult),
        ("func main() -> Int32 {}", .notAType(name: "Int32")),
    ])
    func main(source: String, expected: ErrorCode) {
        #expect(errors(source) == [expected])
    }

    @Test("a program is functions, each a name, '()', an optional result type and a body", arguments: [
        ("struct S {}", ErrorCode.expected(what: .declaration, found: "'struct'")),
        ("func main(_ x: Int) {}", .expected(what: .parenthesisPair, found: "'_'")),
        ("func main<T>() {}", .expected(what: .parametersOpen, found: "'<'")),
        ("func main() throws {}", .expected(what: .blockOpen, found: "'throws'")),
        ("func main() -> (Int) {}", .expected(what: .parenthesisPair, found: "'Int'")),
        ("func main() { let x: 3 = 1 }", .expected(what: .type, found: "'3'")),
        ("func main() { let f = { 1 } }", .expected(what: .expression, found: "'{'")),
    ])
    func syntax(source: String, expected: ErrorCode) {
        #expect(errors(source) == [expected])
    }

    @Test("an integer literal must fit in an Int", arguments: [
        "print(9223372036854775808)", "print(-9223372036854775809)", "print(-(9223372036854775808))",
        "print(0xFFFFFFFFFFFFFFFF)",
    ])
    func literals(body: String) {
        #expect(errors("func main() { \(body) }") == [.literalTooLarge])
    }

    @Test("calls match the function's arguments and their types", arguments: [
        ("foo(1)", ErrorCode.notDeclared(name: "foo")),
        ("print()", .argumentCount(name: "print", takes: 1, passes: 0)),
        ("print(1, 2)", .argumentCount(name: "print", takes: 1, passes: 2)),
        ("print(print(1))", .typeMismatch(expected: "Int", found: "Void")),
        ("print(true)", .typeMismatch(expected: "Int", found: "Bool")),
        ("print(1) + 2", .operandTypes(op: "+", needs: "Int", left: "Void", right: "Int")),
        ("print", .functionAsValue(name: "print")),
        ("print(main)", .functionAsValue(name: "main")),
        ("main()", .notCallable(name: "main")),
    ])
    func calls(body: String, expected: ErrorCode) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("a statement is a declaration, an assignment, 'if', 'while', 'break', 'continue' or an expression",
          arguments: [
        ("{ print(1) }", ErrorCode.expected(what: .expression, found: "'{'")),
        ("else { }", .expected(what: .expression, found: "'else'")),
        ("let a = 1, b = 2", .expected(what: .statementEnd, found: "','")),
        ("if let x = y {}", .expected(what: .expression, found: "'let'")),
        ("if true, false {}", .expected(what: .blockOpen, found: "','")),
    ])
    func statements(body: String, expected: ErrorCode) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("an expression is a literal, a name, a call, 'copy', an operator or parentheses", arguments: [
        ("print(value: 1)", ErrorCode.expected(what: .argumentsClose, found: "':'")),
        ("print(copy 1)", .expected(what: .copiedName, found: "'1'")),
        ("print(1)(2)", .expected(what: .statementEnd, found: "'('")),
        ("let t = (1, 2)", .expected(what: .parenthesizedClose, found: "','")),
        ("let t = ()", .expected(what: .expression, found: "')'")),
        ("let y = if true { 1 } else { 2 }", .expected(what: .expression, found: "'if'")),
    ])
    func expressions(body: String, expected: ErrorCode) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("a type is Int, Bool, Void or '()'", arguments: [
        ("let x: Int = 1; let y: Bool = true; print(x)", []),
        ("let x: Int8 = 1", [ErrorCode.notAType(name: "Int8")]),
        ("let x: List = 1", [.notAType(name: "List")]),
    ])
    func types(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() { \(body) }") == expected)
    }

    @Test("both operands of an operator are checked, and errors are listed in source order")
    func everyError() {
        #expect(errors("func main() { print(a + b) }\nfunc main() {}") == [
            .notDeclared(name: "a"), .notDeclared(name: "b"), .mainDeclaredTwice,
        ])
    }

    @Test("a call's arguments are checked even when the call doesn't match its function", arguments: [
        ("main(a)", [ErrorCode.notCallable(name: "main"), .notDeclared(name: "a")]),
        ("print(a, b)", [.argumentCount(name: "print", takes: 1, passes: 2), .notDeclared(name: "a"),
                         .notDeclared(name: "b")]),
    ])
    func everyArgument(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() { \(body) }") == expected)
    }

    @Test("a program's only function is 'main', declared once, and a second 'main' is still checked")
    func onlyMain() {
        #expect(errors("func f() {}\nfunc main() {}\nfunc main() -> Bool { print(a) }") == [
            .functionNotMain, .mainDeclaredTwice, .mainResult, .notDeclared(name: "a"),
        ])
    }
}
