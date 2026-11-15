import Testing
import RayoDiagnostics

struct UnusedValueTests {
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

    @Test("a dropped value is checked, a local's value is moved, and '_' declares nothing", arguments: [
        ("let x = 1\n_ = x", [ErrorCode]()),
    ])
    func droppedChecked(body: String, expected: [ErrorCode]) {
        #expect(errors("func main() {\n\(body)\n}") == expected)
    }
}
