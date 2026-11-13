import RayoSema

/// An operator that computes a value from two operands of one type. Arithmetic carries its overflow mode, and the
/// operands' type says the rest of how the operator computes, such as whether it orders them as signed.
public enum IRBinaryOperator: Hashable, Sendable, CustomStringConvertible {
    case add(OverflowMode)
    case subtract(OverflowMode)
    case multiply(OverflowMode)
    case divide(OverflowMode)
    /// The remainder of a division, which takes the dividend's sign. No remainder overflows: every remainder by -1
    /// is 0.
    case remainder
    case equal, notEqual, less, lessEqual, greater, greaterEqual

    /// The operator as an error names it, such as `+` or `wrapping +`.
    public var description: String {
        switch self {
        case .add(let mode): mode.naming("+")
        case .subtract(let mode): mode.naming("-")
        case .multiply(let mode): mode.naming("*")
        case .divide(let mode): mode.naming("/")
        case .remainder: "%"
        case .equal: "=="
        case .notEqual: "!="
        case .less: "<"
        case .lessEqual: "<="
        case .greater: ">"
        case .greaterEqual: ">="
        }
    }

    /// The types of the operands the operator takes, both of one of them.
    public var operandTypes: [RayoType] {
        switch self {
        case .add, .subtract, .multiply, .divide, .remainder, .less, .lessEqual, .greater, .greaterEqual: [.int]
        case .equal, .notEqual: [.int, .bool]
        }
    }

    /// The type of the value the operator gives on operands of `type`.
    public func resultType(on type: RayoType) -> RayoType {
        switch self {
        case .add, .subtract, .multiply, .divide, .remainder: type
        case .equal, .notEqual, .less, .lessEqual, .greater, .greaterEqual: .bool
        }
    }
}
