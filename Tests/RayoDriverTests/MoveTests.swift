import Testing
import RayoDiagnostics
import RayoDriver

struct MoveTests {
    @Test("a declaration, an assignment and a 'return' move a local's value, in debug and in release",
          arguments: [["--debug"], ["--release"]])
    func moves(mode: [String]) {
        let source = """
            func main() {
                var a = 1
                let b = a
                a = 2
                var c = 0
                c = b
                print(a)
                print(c)
                print(answer())
            }
            func answer() -> Int {
                let x = 42
                return x
            }
            """
        #expect(run(source, options: mode) == Driver.Result(exitCode: 0, output: "2\n1\n42\n", errors: ""))
    }

    @Test("a use of a moved local is an error at the use", arguments: [
        ("let x = 1\nlet y = x\nprint(x)", "4:7: error[E0302]: 'x' was moved"),
        ("let x = 1\nlet y = (x)\nprint(x)", "4:7: error[E0302]: 'x' was moved"),
        ("let x = 1\n_ = x\nprint(x)", "4:7: error[E0302]: 'x' was moved"),
        ("let x = 1\nlet y = x\nlet z = x", "4:9: error[E0302]: 'x' was moved"),
        ("var x = 1\nlet y = x\nx += 1", "4:1: error[E0302]: 'x' was moved"),
        ("let x = true\nlet y = x\nif x { }", "4:4: error[E0302]: 'x' was moved"),
        ("let x = 1\nlet y = x\nprint(copy x + 1)", "4:7: error[E0302]: 'x' was moved"),
    ])
    func useAfterMove(body: String, expected: String) {
        #expect(diagnostics("func main() {\n\(body)\n}").map(\.description) == [expected])
    }

    @Test("a 'return' moves its local, and a use after it on no path is no error", arguments: [
        ("func f() -> Int {\n    let x = 1\n    let y = x\n    return x\n}", ["5:12: error[E0302]: 'x' was moved"]),
        ("func f() -> Int {\n    let x = 1\n    return x\n    print(x)\n}", []),
    ])
    func returned(declaration: String, expected: [String]) {
        #expect(diagnostics("func main() {}\n" + declaration).map(\.description) == expected)
    }

    @Test("a local moved on one path of an 'if' may have been moved after it, and one moved on both was moved",
          arguments: [
        ("if true { let y = x }", "'x' may have been moved", "E0303"),
        ("if true { let y = x } else { var z = 0\nz = x }", "'x' was moved", "E0302"),
    ])
    func branches(statement: String, message: String, code: String) {
        let reported = diagnostics("func main() {\nvar x = 1\n\(statement)\nprint(x)\n}")
        #expect(reported.map { "\($0.code.identifier): \($0.code.message)" } == ["\(code): \(message)"])
        #expect(reported.map(\.range.start.line) == [statement.split(separator: "\n").count + 3])
    }

    @Test("a move in a loop's body leaves the local without a value on the next pass, unless the body assigns it")
    func loops() {
        let moves = "var i = 0\nvar x = 1\nwhile i < 2 {\ni += 1\nlet y = x\n}"
        #expect(diagnostics("func main() {\n\(moves)\n}").map(\.description) == [
            "6:9: error[E0303]: 'x' may have been moved",
        ])
        #expect(output("var i = 0\nvar x = 1\nwhile i < 2 {\ni += 1\nlet y = x\nprint(y)\nx = 2\n}") == "1\n2\n")
    }

    @Test("a 'break' after a move leaves the loop without the local's value", arguments: [
        ("while true {\nlet y = x\nbreak\n}", "'x' was moved"),
        ("while x > 0 {\nlet y = x\nbreak\n}", "'x' may have been moved"),
    ])
    func breaks(loop: String, message: String) {
        let reported = diagnostics("func main() {\nvar x = 1\n\(loop)\nprint(x)\n}")
        #expect(reported.map(\.code.message) == [message])
        #expect(reported.map(\.range.start.line) == [7])
    }

    @Test("a 'continue' after a move goes on to the next pass without the local's value")
    func continues() {
        let body = "var x = 1\nvar i = 0\nwhile i < 3 {\ni += 1\nprint(copy x)\nif i == 1 {\nlet y = x\ncontinue\n}\nx = 5\n}"
        #expect(diagnostics("func main() {\n\(body)\n}").map(\.description) == [
            "6:7: error[E0303]: 'x' may have been moved",
        ])
        #expect(output(body.replacingOccurrences(of: "continue\n", with: "")) == "1\n5\n5\n")
    }

    @Test("the uses that the same moves reach are one error, at the first of them", arguments: [
        ("let x = 1\nlet y = x\nprint(x + x)\nprint(x)", "4:7: error[E0302]: 'x' was moved"),
        ("var x = 1\nwhile x > 0 {\nlet y = x\n}", "3:7: error[E0303]: 'x' may have been moved"),
        ("var x = 1\nif true { let y = x }\nprint(x)\nlet z = x", "4:7: error[E0303]: 'x' may have been moved"),
    ])
    func reportedOnce(body: String, expected: String) {
        #expect(diagnostics("func main() {\n\(body)\n}").map(\.description) == [expected])
    }

    @Test("a use that other moves reach is another error")
    func reportedAgain() {
        let body = "var x = 1\nlet y = x\nprint(x)\nx = 2\nlet z = x\nprint(x)"
        #expect(diagnostics("func main() {\n\(body)\n}").map(\.description) == [
            "4:7: error[E0302]: 'x' was moved", "7:7: error[E0302]: 'x' was moved",
        ])
    }

    @Test("a path that returns after a move leaves the local's value on the others")
    func returnsAfterMove() {
        let source = "func main() {\n    f(true)\n    f(false)\n}\nfunc f(_ c: Bool) {\n    let x = 1\n    if c {\n        let y = x\n        return\n    }\n    print(x)\n}"
        #expect(run(source) == Driver.Result(exitCode: 0, output: "1\n", errors: ""))
    }

    @Test("an argument is borrowed, not moved, so the local keeps its value")
    func argumentsBorrow() {
        #expect(output("let x = 1\nprint(x)\nprint(x + x)\nlet y = x\nprint(y)") == "1\n2\n1\n")
    }

    @Test("a borrowed parameter can't be moved, and the error covers it; 'copy' takes its value", arguments: [
        ("func f(x: Int) -> Int { x }", [ErrorCode.moveFromParameter(name: "x")], ["x"]),
        ("func f(x: Int) -> Int { return x }", [.moveFromParameter(name: "x")], ["x"]),
        ("func f(x: Int) { let y = x }", [.moveFromParameter(name: "x")], ["x"]),
        ("func f(x: Int) { _ = x }", [.moveFromParameter(name: "x")], ["x"]),
        ("func f(x: Int) {\n    var y = 0\n    y = x\n}", [.moveFromParameter(name: "x")], ["x"]),
        ("func f(x: Int) -> Int {\n    let y = copy x\n    print(x)\n    return copy x\n}", [], []),
    ])
    func borrowedParameter(declaration: String, expected: [ErrorCode], covered: [String]) {
        let source = "func main() {}\n" + declaration
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == expected)
        #expect(coveredText(reported, in: source) == covered)
    }
}
