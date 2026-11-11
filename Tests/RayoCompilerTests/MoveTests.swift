import Testing
import RayoDiagnostics

struct MoveTests {
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
        #expect(errorLines(inMain: body) == [expected])
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
        ("if true { let y = x }", "E0303: 'x' may have been moved", 4),
        ("if true { let y = x } else { var z = 0\nz = x }", "E0302: 'x' was moved", 5),
    ])
    func branches(statement: String, expected: String, line: Int) {
        let reported = diagnostics("func main() {\nvar x = 1\n\(statement)\nprint(x)\n}")
        #expect(reported.map { "\($0.code.identifier): \($0.code.message)" } == [expected])
        #expect(reported.map(\.range.start.line) == [line])
    }

    @Test("a move in a loop's body leaves the local without a value on the next pass")
    func loops() {
        #expect(errorLines(inMain: "var i = 0\nvar x = 1\nwhile i < 2 {\ni += 1\nlet y = x\n}") == [
            "6:9: error[E0303]: 'x' may have been moved",
        ])
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
        let body = """
            var x = 1
            var i = 0
            while i < 3 {
            i += 1
            print(copy x)
            if i == 1 {
            let y = x
            continue
            }
            x = 5
            }
            """
        #expect(errorLines(inMain: body) == ["6:7: error[E0303]: 'x' may have been moved"])
        #expect(errorLines(inMain: body.replacing("continue\n", with: "")) == [])
    }

    @Test("the uses that the same moves reach are one error, at the first of them", arguments: [
        ("let x = 1\nlet y = x\nprint(x + x)\nprint(x)", "4:7: error[E0302]: 'x' was moved"),
        ("var x = 1\nwhile x > 0 {\nlet y = x\n}", "3:7: error[E0303]: 'x' may have been moved"),
        ("var x = 1\nif true { let y = x }\nprint(x)\nlet z = x", "4:7: error[E0303]: 'x' may have been moved"),
    ])
    func reportedOnce(body: String, expected: String) {
        #expect(errorLines(inMain: body) == [expected])
    }

    @Test("a use that other moves reach is another error")
    func reportedAgain() {
        #expect(errorLines(inMain: "var x = 1\nlet y = x\nprint(x)\nx = 2\nlet z = x\nprint(x)") == [
            "4:7: error[E0302]: 'x' was moved", "7:7: error[E0302]: 'x' was moved",
        ])
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
