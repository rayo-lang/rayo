/// What a binary operator does to its operands, once checked. Arithmetic and comparisons compute their value from
/// both operands. `&&` and `||` evaluate the right operand only when the left one doesn't decide the value.
public enum CheckedBinaryOperator: Hashable, Sendable {
    case add, subtract, multiply, divide, remainder
    case equal, notEqual, less, lessEqual, greater, greaterEqual
    case and, or
}
