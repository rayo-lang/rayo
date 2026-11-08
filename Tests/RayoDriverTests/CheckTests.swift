import Testing
import RayoDriver

/// The errors `rayoc check` reports for `source`, saved as `main.rayo`.
func errors(_ source: String) -> [String] {
    let result = Driver.run(["check", "main.rayo"]) { $0 == "main.rayo" ? Array(source.utf8) : nil }
    #expect(result.exitCode == (result.errors.isEmpty ? 0 : 1))
    #expect(result.output == "")
    let lines = result.errors.split(separator: "\n")
    #expect(lines.allSatisfy { $0.hasPrefix("main.rayo:") })
    return lines.map { String($0.dropFirst("main.rayo:".count)) }
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
        ("", "1:1: error: the program has no 'main' function"),
        ("func main() -> Int { 0 }", "1:16: error: 'main' returns Void"),
        ("func main() -> Int32 {}", "1:16: error: 'Int32' isn't a type"),
    ])
    func main(source: String, expected: String) {
        #expect(errors(source) == [expected])
    }

    @Test("a program is functions, each a name, '()', an optional result type and a body", arguments: [
        ("struct S {}", "1:1: error: expected 'func' to begin a declaration, found 'struct'"),
        ("@main\nfunc main() {}", "1:1: error: expected 'func' to begin a declaration, found '@'"),
        ("func main(_ x: Int) {}", "1:11: error: expected ')' after '(', found '_'"),
        ("func main<T>() {}", "1:10: error: expected '(' after the function's name, found '<'"),
        ("func main() throws {}", "1:13: error: expected '{' to begin a block, found 'throws'"),
        ("func main() -> (Int) {}", "1:17: error: expected ')' after '(', found 'Int'"),
        ("func main() { let x: [3 of Int] = 1 }", "1:22: error: expected a type, found '['"),
        ("func main() { let x: Int? = 1 }", "1:25: error: expected a newline or ';' after the statement, found '?'"),
        ("func main() { let f = { 1 } }", "1:23: error: expected an expression, found '{'"),
    ])
    func syntax(source: String, expected: String) {
        #expect(errors(source) == [expected])
    }

    @Test("an integer literal must fit in an Int", arguments: [
        ("print(9223372036854775808)", "1:21: error: the literal doesn't fit in an Int"),
        ("print(-9223372036854775809)", "1:21: error: the literal doesn't fit in an Int"),
        ("print(-(9223372036854775808))", "1:22: error: the literal doesn't fit in an Int"),
        ("print(0xFFFFFFFFFFFFFFFF)", "1:21: error: the literal doesn't fit in an Int"),
    ])
    func literals(body: String, expected: String) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("calls match the function's labels, arguments and types", arguments: [
        ("foo(1)", "1:15: error: 'foo' isn't declared"),
        ("print()", "1:15: error: 'print' takes 1 argument, but the call passes 0"),
        ("print(1, 2)", "1:15: error: 'print' takes 1 argument, but the call passes 2"),
        ("print(value: 1)", "1:28: error: argument 1 of 'print' takes no label, not 'value'"),
        ("print(print(1))", "1:21: error: printing a value of type Void isn't supported yet"),
        ("print(true)", "1:21: error: printing a value of type Bool isn't supported yet"),
        ("print(1) + 2", "1:15: error: '+' needs Int operands, found Void and Int"),
        ("print", "1:15: error: using a function as a value isn't supported yet"),
        ("print(main)", "1:21: error: using a function as a value isn't supported yet"),
    ])
    func calls(body: String, expected: String) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("what the checker doesn't have yet is reported as such", arguments: [
        ("for i in 0..<3 { }", "1:15: error: 'for' isn't supported yet"),
        ("return", "1:15: error: 'return' isn't supported yet"),
        ("do { }", "1:15: error: 'do' isn't supported yet"),
        ("print(copy 1)", "1:21: error: 'copy' of a literal isn't supported yet"),
        ("var x = &y", "1:23: error: '&' isn't supported yet"),
    ])
    func unsupportedInMain(body: String, expected: String) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("a type is Int, Bool, Void or '()'", arguments: [
        ("let x: Int = 1; let y: Bool = true; print(x)", []),
        ("let x: Int8 = 1", ["1:22: error: 'Int8' isn't a type"]),
        ("let x: List = 1", ["1:22: error: 'List' isn't a type"]),
    ])
    func types(body: String, expected: [String]) {
        #expect(errors("func main() { \(body) }") == expected)
    }

    @Test("both operands of an operator are checked, and errors are listed in source order")
    func everyError() {
        #expect(errors("func main() { print(a + b) }\nfunc main() {}") == [
            "1:21: error: 'a' isn't declared",
            "1:25: error: 'b' isn't declared",
            "2:6: error: 'main' is declared more than once",
        ])
    }

    @Test("a call's arguments are checked even when the call doesn't match its function", arguments: [
        ("print(value: a)", ["1:28: error: argument 1 of 'print' takes no label, not 'value'",
                             "1:28: error: 'a' isn't declared"]),
        ("print(a, b)", ["1:15: error: 'print' takes 1 argument, but the call passes 2",
                         "1:21: error: 'a' isn't declared", "1:24: error: 'b' isn't declared"]),
    ])
    func everyArgument(body: String, expected: [String]) {
        #expect(errors("func main() { \(body) }") == expected)
    }

    @Test("a program's only function is 'main', declared once, and a second 'main' is still checked")
    func onlyMain() {
        #expect(errors("func f() {}\nfunc main() {}\nfunc main() -> Bool { print(a) }") == [
            "1:6: error: a program's only function is 'main'",
            "3:6: error: 'main' is declared more than once",
            "3:16: error: 'main' returns Void",
            "3:29: error: 'a' isn't declared",
        ])
    }
}
