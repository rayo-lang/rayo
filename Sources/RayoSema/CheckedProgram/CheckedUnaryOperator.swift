/// What a unary operator does to its operand, once checked.
public enum CheckedUnaryOperator: Hashable, Sendable {
    /// Negates an Int.
    case negate
    /// Negates a Bool.
    case not
}
