import Testing
import RayoSyntax

/// The expression that `_ = expression` drops, with each operator's operands in parentheses around it, as the parser
/// groups them.
private func grouping(of expression: String) throws -> String {
    let (file, diagnostics) = try parsed("func f() {\n    _ = \(expression)\n}")
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
    case .consume(let place): "(consume \(grouped(place)))"
    case .reference(let place): "(& \(grouped(place)))"
    case .mutableReference(let place): "(mutable \(grouped(place)))"
    // A postfix binds tighter than any operator, so it is written as the source writes it.
    case .member(let base, let name, _): "\(grouped(base)).\(name)"
    case .element(let base, let index): "\(grouped(base))[\(grouped(index))]"
    case .call(let callee, let arguments): "\(grouped(callee))(\(arguments.map(grouped).joined(separator: ", ")))"
    // The tests write no other expression.
    default: "\(expression.kind)"
    }
}

/// `argument` as source text, its label before its value where it has one, with the value's operators grouped.
private func grouped(_ argument: Argument) -> String {
    let value = grouped(argument.value)
    return if let label = argument.label { "\(label): \(value)" } else { value }
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
        ("!false && false", "((! false) && false)"), ("consume a + 1", "((consume a) + 1)"), ("&a + 1", "((& a) + 1)"),
        ("mutable a + 1", "((mutable a) + 1)"), ("&make().x + 1", "((& make().x) + 1)"),
        ("mutable make(2)[0] * 3", "((mutable make(2)[0]) * 3)"),
        ("&make(1 + 2, by: a).x - 1", "((& make((1 + 2), by: a).x) - 1)"),
        ("mutable &a.x + 1", "((mutable (& a.x)) + 1)"),
    ])
    func `prefix operators, 'copy', 'consume', '&' and 'mutable' bind tighter than binary operators`(
        expression: String, expected: String,
    ) throws {
        #expect(try grouping(of: expression) == expected)
    }
}
