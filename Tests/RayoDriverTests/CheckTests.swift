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
    @Test("a program that checks reports nothing")
    func clean() {
        #expect(errors("func main() { print(-9223372036854775808) }") == [])
    }

    @Test("a program needs a 'main' that takes no parameters, and returns Void, Never or Int32", arguments: [
        ("", "1:1: error: the program has no 'main' function"),
        ("func main(_ x: Int) {}", "1:11: error: 'main' takes no parameters"),
        ("func main() -> Int { 0 }", "1:16: error: 'main' returns Void, Never or Int32"),
        ("func main() -> Int32 {}", "1:16: error: the type 'Int32' isn't supported yet"),
        ("func main() -> Never {}", "1:16: error: the type 'Never' isn't supported yet"),
    ])
    func main(source: String, expected: String) {
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
        ("print(print(1))", "1:21: error: expected Int, found Void"),
        ("print(1) + 2", "1:15: error: '+' needs Int operands, found Void and Int"),
        ("print<Int>(1)", "1:15: error: 'print' takes no generic arguments"),
        ("print", "1:15: error: using a function as a value isn't supported yet"),
        ("print(main)", "1:21: error: using a function as a value isn't supported yet"),
    ])
    func calls(body: String, expected: String) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("what the checker doesn't have yet is reported as such", arguments: [
        ("let x = 1", "1:15: error: a 'let' declaration isn't supported yet"),
        ("while 1 { }", "1:15: error: 'while' isn't supported yet"),
        ("print(1 < 2)", "1:21: error: '<' isn't supported yet"),
        ("print(copy 1)", "1:21: error: 'copy' isn't supported yet"),
        ("print(true)", "1:21: error: Bool isn't supported yet"),
    ])
    func unsupportedInMain(body: String, expected: String) {
        #expect(errors("func main() { \(body) }") == [expected])
    }

    @Test("both operands of an operator are checked, and errors are listed in source order")
    func everyError() {
        #expect(errors("func main() { print(a + b) }\nstruct S(var x: Int)") == [
            "1:21: error: 'a' isn't declared",
            "1:25: error: 'b' isn't declared",
            "2:8: error: a struct isn't supported yet",
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

    @Test("declarations other than one 'main' aren't supported yet, and a second 'main' is still checked")
    func unsupportedDeclarations() {
        #expect(errors("struct S(var x: Int)\nfunc f() {}\nfunc main() {}\nfunc main() -> Bool { print(a) }") == [
            "1:8: error: a struct isn't supported yet",
            "2:6: error: a function other than 'main' isn't supported yet",
            "4:6: error: 'main' is declared more than once",
            "4:16: error: the type 'Bool' isn't supported yet",
            "4:29: error: 'a' isn't declared",
        ])
    }
}
