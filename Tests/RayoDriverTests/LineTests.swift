import Testing
import RayoDiagnostics
import RayoDriver

struct LineTests {
    @Test("a statement goes on past a line that ends in an operator, '=' or an open '('", arguments: [
        ("let total = 1 +\n    2 * 3\nprint(total)", "7"),
        ("let ok = 2 >\n    1\nif ok { print(1) }", "1"),
        ("var x = 0\nx =\n    4\nprint(x)", "4"),
        ("print(\n    1 + 1,\n)", "2"),
    ])
    func continued(body: String, expected: String) {
        #expect(output(body) == expected + "\n")
    }

    @Test("a line that starts with '-' starts a statement, and one that starts with another operator joins")
    func leadingOperator() {
        // A line that starts with '-' is a statement of its own, whose value goes unused.
        let source = "func main() {\nlet a = 3\n-2\n}"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.unusedValue(type: "Int")])
        #expect(coveredText(reported, in: source) == ["-2"])

        // A line that starts with '*' joins the declaration above.
        #expect(output("let a = 3\n    * 2\nprint(a)") == "6\n")
    }

    @Test("an 'else' or a '{' on the next line belongs to the statement above")
    func nextLine() {
        #expect(output("if false { print(1) }\nelse { print(2) }") == "2\n")
        #expect(output("if true\n{ print(3) }") == "3\n")
    }
}
