import Testing
import RayoDiagnostics

struct BoolTests {
    @Test("operands and conditions are checked", arguments: [
        ("if 1 { }", ErrorCode.typeMismatch(expected: "Bool", found: "Int")),
        ("while 0 { }", .typeMismatch(expected: "Bool", found: "Int")),
        ("let b = 1 == true", .operandsDiffer(op: "==", left: "Int", right: "Bool")),
        ("let b = true < false", .integerOperands(op: "<", left: "Bool", right: "Bool")),
        ("let b = 1 && true", .operandTypes(op: "&&", needs: "Bool", left: "Int", right: "Bool")),
        ("let b = !1", .typeMismatch(expected: "Bool", found: "Int")),
        ("let b = -true", .integerOperand(op: "-", found: "Bool")),
        ("let b = print(1) == print(2)", .incomparable(op: "==", type: "Void")),
    ])
    func rejected(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}") == [expected])
    }
}
