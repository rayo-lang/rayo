/// What a binary operator does to its operands, once checked: arithmetic or a comparison, which computes its value
/// from both operands, or `&&` or `||`, which evaluates the right operand only when the left one doesn't decide the
/// value.
public enum CheckedBinaryOperator: Hashable, Sendable {
    case add, subtract, multiply, divide, remainder
    case equal, notEqual, less, lessEqual, greater, greaterEqual
    case and, or
}
