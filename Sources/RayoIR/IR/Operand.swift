import RayoSema

public enum Operand: Sendable {
    case constant(Constant)
    /// Reads the local's value, which the local keeps.
    case read(Place)
    /// Takes the local's value, which leaves the local without one until it is assigned again.
    case move(Place)
}

public enum Constant: Sendable {
    case int(Int64)
    case bool(Bool)

    public var type: RayoType {
        switch self {
        case .int: return .int
        case .bool: return .bool
        }
    }
}
