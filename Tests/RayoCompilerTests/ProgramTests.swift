import Testing
import RayoDiagnostics

struct ProgramTests {
    @Test("a program that checks reports nothing", arguments: [
        "func main() { print(-9223372036854775808) }",
        "func main() -> Void {}",
        "func main() -> () {}",
    ])
    func clean(source: String) {
        #expect(errors(source) == [])
    }

    @Test("a 'main' returns Void", arguments: [
        ("func main() -> Int { 0 }", ErrorCode.mainReturnsNonVoid),
        ("func main() -> Int32 {}", .notAType(name: "Int32")),
    ])
    func main(source: String, expected: ErrorCode) {
        #expect(errors(source) == [expected])
    }

    @Test(arguments: [
        ("enum E {}", ErrorCode.missingDeclaration(found: .token("enum"))),
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
    func `a program is structs and functions, each function a name, parameters, a result type and a body`(
        source: String, expected: ErrorCode,
    ) {
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
        ("print()", .noMatchingFunction(name: "print", arguments: "")),
        ("print(1, 2)", .noMatchingFunction(name: "print", arguments: "Int, Int")),
        ("print(1, true)", .noMatchingFunction(name: "print", arguments: "Int, Bool")),
        ("print(print(1))", .noMatchingFunction(name: "print", arguments: "Void")),
        ("print(value: true)", .noMatchingFunction(name: "print", arguments: "value: Bool")),
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

    @Test(arguments: [
        ("let x: Int = 1; let y: Bool = true; print(x); print(y)", []),
        ("let x: Int8 = 1", [ErrorCode.notAType(name: "Int8")]),
        ("let x: Vec = 1", [.notAType(name: "Vec")]),
        ("var x: List", []),
    ])
    func `a type is Int, Bool, Void, '()' or a struct`(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() { \(body) }\nstruct List") == expected)
    }

    @Test("both operands of an operator are checked, and errors are listed in source order")
    func everyError() {
        #expect(errors("func main() { print(a + b) }\nfunc main() {}") == [
            .notDeclared(name: "a"), .notDeclared(name: "b"), .functionDeclaredTwice(signature: "main()"),
        ])
    }

    @Test("a call's arguments are checked even when the call doesn't match its function", arguments: [
        ("main(a)", [ErrorCode.argumentCount(name: "main", takes: 0, passes: 1), .notDeclared(name: "a")]),
        ("print(a, b)", [.notDeclared(name: "a"), .notDeclared(name: "b")]),
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
