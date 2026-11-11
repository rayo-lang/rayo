/// The type of a value in a checked program.
public enum RayoType: Hashable, Sendable, CustomStringConvertible {
    case int
    case bool
    case void
    case structure(StructID)

    public var description: String {
        switch self {
        case .int: "Int"
        case .bool: "Bool"
        case .void: "Void"
        case .structure(let id): id.name
        }
    }
}
