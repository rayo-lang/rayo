import Testing
import RayoDriver

struct PrecedenceTests {
    @Test("'*', '/' and '%' bind tighter than '+' and '-', and operators of one level group from the left",
          arguments: [
        ("2 + 3 * 4", "14"), ("2 * 3 + 4", "10"), ("10 - 4 - 3", "3"), ("(2 + 3) * 4", "20"),
        ("20 % 6 / 2", "1"), ("24 / 4 / 2", "3"),
    ])
    func arithmetic(expression: String, value: String) {
        #expect(output("print(\(expression))") == value + "\n")
    }

    @Test("arithmetic binds tighter than comparison, comparison than '&&', and '&&' than '||'", arguments: [
        ("1 + 2 < 2 * 2", true), ("1 < 2 == true", true), ("2 >= 2 != false", true),
        ("true || false && false", true), ("false && true || true", true), ("1 == 1 && 2 > 3", false),
    ])
    func logic(expression: String, value: Bool) {
        #expect(output("if \(expression) { print(1) } else { print(0) }") == (value ? "1\n" : "0\n"))
    }

    @Test("prefix operators and 'copy' bind tighter than binary operators", arguments: [
        ("print(- -5)", "5"), ("print(-(5) + 2)", "-3"), ("let a = 3\nprint(copy a + 1)", "4"),
        ("if !false && false { print(1) } else { print(0) }", "0"),
    ])
    func prefix(body: String, expected: String) {
        #expect(output(body) == expected + "\n")
    }
}

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

    @Test("a line that starts with a binary operator other than '-' joins the line above")
    func leadingOperator() {
        #expect(output("let a = 3\n    * 2\nprint(a)") == "6\n")
    }

    @Test("an 'else' or a '{' on the next line belongs to the statement above")
    func nextLine() {
        #expect(output("if false { print(1) }\nelse { print(2) }") == "2\n")
        #expect(output("if true\n{ print(3) }") == "3\n")
    }
}
