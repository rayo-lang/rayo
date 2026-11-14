/// The type of a value in a checked program.
public indirect enum RayoType: Hashable, Sendable, CustomStringConvertible {
    case int
    case uint
    case bool
    case void
    case structure(StructID)
    /// `[count of element]`: `count` values of the element's type, which lie end to end.
    case array(count: Int, element: RayoType)

    public var description: String {
        switch self {
        case .int: "Int"
        case .uint: "UInt"
        case .bool: "Bool"
        case .void: "Void"
        case .structure(let id): id.name
        case .array(let count, let element): "[\(count) of \(element)]"
        }
    }

    /// Whether the type is an integer type, which arithmetic and orderings take.
    public var isInteger: Bool {
        switch self {
        case .int, .uint: true
        case .bool, .void, .structure, .array: false
        }
    }
}
