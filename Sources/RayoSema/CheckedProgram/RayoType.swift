/// The type of a value in a checked program.
public enum RayoType: Hashable, Sendable, CustomStringConvertible {
    case int
    case uint
    case bool
    case void
    case structure(StructID)

    public var description: String {
        switch self {
        case .int: "Int"
        case .uint: "UInt"
        case .bool: "Bool"
        case .void: "Void"
        case .structure(let id): id.name
        }
    }

    /// Whether the type is an integer type, which arithmetic and orderings take.
    public var isInteger: Bool {
        switch self {
        case .int, .uint: true
        case .bool, .void, .structure: false
        }
    }
}
