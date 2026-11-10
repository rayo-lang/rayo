/// The type of a value in a checked program.
public enum RayoType: Hashable, Sendable, CustomStringConvertible {
    case int
    case bool
    case void

    public var description: String {
        switch self {
        case .int: return "Int"
        case .bool: return "Bool"
        case .void: return "Void"
        }
    }
}
