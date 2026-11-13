import RayoSema

/// An operator that computes a value from one operand, whose type says how it computes it.
public enum IRUnaryOperator: Hashable, Sendable, CustomStringConvertible {
    case negate(OverflowMode)
    case not

    /// The operator as an error names it, such as `-` or `wrapping -`.
    public var description: String {
        switch self {
        case .negate(let mode): mode.naming("-")
        case .not: "!"
        }
    }

    /// The type of the value the operator gives on an operand of `type`.
    public func resultType(on type: RayoType) -> RayoType {
        switch self {
        case .negate: type
        case .not: .bool
        }
    }
}
