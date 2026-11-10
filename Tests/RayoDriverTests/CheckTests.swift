import Testing
import RayoDiagnostics
import RayoDriver

/// The errors `rayoc check` reports for `source`, saved as `main.rayo`.
func errors(_ source: String) -> [ErrorCode] {
    diagnostics(source).map(\.code)
}

/// The source text each of `diagnostics` covers in `source`.
func coveredText(_ diagnostics: [Diagnostic], in source: String) -> [String] {
    let bytes = Array(source.utf8)
    return diagnostics.map { String(decoding: bytes[$0.range.start.offset..<$0.range.end.offset], as: UTF8.self) }
}

/// The diagnostics `rayoc check` reports for `source`, saved as `main.rayo`.
func diagnostics(_ source: String) -> [Diagnostic] {
    let result = Driver.run(["check", "main.rayo"]) { $0 == "main.rayo" ? Array(source.utf8) : nil }
    #expect(result.exitCode == (result.diagnostics.isEmpty ? 0 : 1))
    #expect(result.output == "")
    return result.diagnostics
}

/// The errors that `body`, as `main`'s body, reports, each as its position, code and message.
func errorLines(inMain body: String) -> [String] {
    diagnostics("func main() {\n\(body)\n}").map(\.description)
}

/// The codes of the errors that `body`, as `main`'s body, reports, and the text of `main.rayo` each covers.
func codesAndCoverage(inMain body: String) -> (codes: [ErrorCode], covered: [String]) {
    let source = "func main() {\n\(body)\n}"
    let reported = diagnostics(source)
    return (reported.map(\.code), coveredText(reported, in: source))
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
        ("func main() -> Int { 0 }", .mainReturnsNonVoid),
        ("func main() -> Int32 {}", .notAType(name: "Int32")),
    ])
    func main(source: String, expected: ErrorCode) {
        #expect(errors(source) == [expected])
    }

    @Test("a program is functions, each a name, parameters, an optional result type and a body", arguments: [
        ("struct S {}", ErrorCode.missingFunc(found: .token("struct"))),
        ("func 1() {}", .missingFunctionName(found: .token("1"))),
        ("func main(x) {}", .missingParameterType(found: .token(")"))),
        ("func f(1: Int) {}", .missingParameterName(found: .token("1"))),
        ("func f(a: Int b: Int) {}", .unclosedParameters(found: .token("b"))),
        ("func main<T>() {}", .missingParameterList(found: .token("<"))),
        ("func main() throws {}", .missingBlock(found: .token("throws"))),
        ("func main() -> (Int) {}", .unclosedEmptyParentheses(found: .token("Int"))),
        ("func main() { let x: 3 = 1 }", .missingType(found: .token("3"))),
        ("func main() { let f = { 1 } }", .missingExpression(found: .token("{"))),
    ])
    func syntax(source: String, expected: ErrorCode) {
        #expect(errors(source) == [expected])
    }

    @Test("an integer literal must fit in an Int, and the error covers the literal", arguments: [
        ("print(9223372036854775808)", "9223372036854775808"),
        ("print(-9223372036854775809)", "-9223372036854775809"),
        ("print(-(9223372036854775808))", "(9223372036854775808)"),
        ("print(0xFFFFFFFFFFFFFFFF)", "0xFFFFFFFFFFFFFFFF"),
    ])
    func literals(body: String, literal: String) {
        let source = "func main() { \(body) }"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.literalExceedsInt])
        #expect(coveredText(reported, in: source) == [literal])
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
        ("main(1)", .argumentCount(name: "main", takes: 0, passes: 1)),
    ])
    func calls(body: String, expected: ErrorCode) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("a statement is a declaration, an assignment, 'if', 'while', 'break', 'continue' or an expression",
          arguments: [
        ("{ print(1) }", ErrorCode.missingExpression(found: .token("{"))),
        ("else { }", .missingExpression(found: .token("else"))),
        ("if let x = y {}", .missingExpression(found: .token("let"))),
        ("if true, false {}", .missingBlock(found: .token(","))),
    ])
    func statements(body: String, expected: ErrorCode) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("an expression is a literal, a name, a call, 'copy', an operator or parentheses", arguments: [
        ("print(1 2)", ErrorCode.unclosedArguments(found: .token("2"))),
        ("print(copy 1)", .missingCopiedName(found: .token("1"))),
        ("print(1)(2)", .unendedStatement(found: .token("("))),
        ("let t = (1, 2)", .unclosedParenthesizedExpression(found: .token(","))),
        ("let t = ()", .missingExpression(found: .token(")"))),
        ("let y = if true { 1 } else { 2 }", .missingExpression(found: .token("if"))),
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
            .notDeclared(name: "a"), .notDeclared(name: "b"), .functionDeclaredTwice(signature: "main()"),
        ])
    }

    @Test("a call's arguments are checked even when the call doesn't match its function", arguments: [
        ("main(a)", [ErrorCode.argumentCount(name: "main", takes: 0, passes: 1), .notDeclared(name: "a")]),
        ("print(a, b)", [.argumentCount(name: "print", takes: 1, passes: 2), .notDeclared(name: "a"),
                         .notDeclared(name: "b")]),
    ])
    func everyArgument(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() { \(body) }") == expected)
    }

    @Test("'main' is declared once, and a second 'main' is still checked")
    func mainOnce() {
        #expect(errors("func f() {}\nfunc main() {}\nfunc main() -> Bool { print(a) }") == [
            .functionDeclaredTwice(signature: "main()"), .mainReturnsNonVoid, .notDeclared(name: "a"),
        ])
    }
}
