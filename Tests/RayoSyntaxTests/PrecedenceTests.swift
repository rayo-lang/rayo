import Testing
import RayoSyntax

/// The expression that `_ = expression` drops, with each operator's operands in parentheses around it, as the parser
/// groups them.
private func grouping(of expression: String) throws -> String {
    let (file, diagnostics) = Parser.parse("func f() {\n    _ = \(expression)\n}")
    try #require(diagnostics.isEmpty, "\(diagnostics)")
    guard case .function(let function)? = file.declarations.first else { throw NotADrop() }
    let statement = try #require(function.body.statements.first)
    guard case .drop(let dropped) = statement.kind else { throw NotADrop() }
    return grouped(dropped)
}

/// The source a test parsed doesn't hold the function of one `_ =` statement it writes.
private struct NotADrop: Error {}

/// `expression` as source text, with each operator and its operands in parentheses.
private func grouped(_ expression: Expr) -> String {
    switch expression.kind {
    case .intLiteral(let digits): "\(digits)"
    case .negativeIntLiteral(let digits): "-\(digits)"
    case .boolLiteral(let value): "\(value)"
    case .name(let name): name
    case .unary(let op, let operand): "(\(op.rawValue) \(grouped(operand)))"
    case .binary(let op, let left, let right): "(\(grouped(left)) \(op.rawValue) \(grouped(right)))"
    case .copy(let place): "(copy \(grouped(place)))"
    // The tests write no other expression.
    default: "\(expression.kind)"
    }
}

struct PrecedenceTests {
    @Test(arguments: [
        ("2 + 3 * 4", "(2 + (3 * 4))"), ("2 * 3 + 4", "((2 * 3) + 4)"), ("10 - 4 - 3", "((10 - 4) - 3)"),
        ("(2 + 3) * 4", "((2 + 3) * 4)"), ("20 % 6 / 2", "((20 % 6) / 2)"), ("24 / 4 / 2", "((24 / 4) / 2)"),
    ])
    func `'*', '/' and '%' bind tighter than '+' and '-', and operators of one level group from the left`(
        expression: String, expected: String,
    ) throws {
        #expect(try grouping(of: expression) == expected)
    }

    @Test(arguments: [
        ("1 + 2 < 2 * 2", "((1 + 2) < (2 * 2))"), ("1 < 2 == true", "((1 < 2) == true)"),
        ("2 >= 2 != false", "((2 >= 2) != false)"), ("true || false && false", "(true || (false && false))"),
        ("false && true || true", "((false && true) || true)"), ("1 == 1 && 2 > 3", "((1 == 1) && (2 > 3))"),
    ])
    func `arithmetic binds tighter than comparison, comparison than '&&', and '&&' than '||'`(
        expression: String, expected: String,
    ) throws {
        #expect(try grouping(of: expression) == expected)
    }

    @Test(arguments: [
        ("- -5", "(- -5)"), ("-(5) + 2", "((- 5) + 2)"), ("copy a + 1", "((copy a) + 1)"),
        ("!false && false", "((! false) && false)"),
    ])
    func `prefix operators and 'copy' bind tighter than binary operators`(expression: String, expected: String) throws {
        #expect(try grouping(of: expression) == expected)
    }
}
