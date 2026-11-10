import Testing
import RayoDiagnostics
import RayoDriver

struct BoolTests {
    @Test("comparisons and logic make Bools", arguments: [
        ("1 < 2", true), ("2 <= 2", true), ("3 > 4", false), ("4 >= 5", false), ("1 == 1", true), ("1 != 1", false),
        ("true == false", false), ("true != false", true), ("!false", true), ("true && false", false),
        ("false || true", true),
    ])
    func logic(expression: String, value: Bool) {
        #expect(output("if \(expression) { print(1) } else { print(0) }") == (value ? "1\n" : "0\n"))
    }

    @Test("'&&' and '||' evaluate their right operand only when the left one doesn't decide")
    func shortCircuit() {
        #expect(output("if false && 1 / 0 == 0 { print(1) }\nif true || 1 / 0 == 0 { print(2) }") == "2\n")
    }

    @Test("operands and conditions are checked", arguments: [
        ("if 1 { }", ErrorCode.typeMismatch(expected: "Bool", found: "Int")),
        ("while 0 { }", .typeMismatch(expected: "Bool", found: "Int")),
        ("let b = 1 == true", .operandsDiffer(op: "==", left: "Int", right: "Bool")),
        ("let b = true < false", .operandTypes(op: "<", needs: "Int", left: "Bool", right: "Bool")),
        ("let b = 1 && true", .operandTypes(op: "&&", needs: "Bool", left: "Int", right: "Bool")),
        ("let b = !1", .typeMismatch(expected: "Bool", found: "Int")),
        ("let b = -true", .typeMismatch(expected: "Int", found: "Bool")),
        ("let b = print(1) == print(2)", .voidComparison(op: "==")),
    ])
    func rejected(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }
}
