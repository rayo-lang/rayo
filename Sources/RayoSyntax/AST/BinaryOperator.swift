public enum BinaryOperator: String, Sendable, Hashable {
    case add = "+", subtract = "-", multiply = "*", divide = "/", remainder = "%"
    case equal = "==", notEqual = "!=", less = "<", lessEqual = "<=", greater = ">", greaterEqual = ">="
    case and = "&&", or = "||"
}
