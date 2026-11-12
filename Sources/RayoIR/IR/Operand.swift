import RayoSema

public enum Operand: Equatable, Sendable {
    case constant(Constant)
    /// Reads the value of the local, or of the field inside it, which keeps the value.
    case read(Place)
    /// Takes the local's value, which leaves the local without one until it is assigned again.
    case move(Place)
}

public enum Constant: Equatable, Sendable {
    case int(Int64)
    case bool(Bool)

    public var type: RayoType {
        switch self {
        case .int: return .int
        case .bool: return .bool
        }
    }
}
