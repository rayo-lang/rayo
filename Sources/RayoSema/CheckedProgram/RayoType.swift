/// The type of a value in a checked program.
public indirect enum RayoType: Hashable, Sendable, CustomStringConvertible {
    /// A number or a truth value, one of the prelude's scalar types.
    case scalar(ScalarType)
    case void
    case structure(StructID)
    /// `[count of element]`: `count` values of the element's type, which lie end to end.
    case array(count: Int, element: RayoType)

    public static let int = RayoType.scalar(.int)
    public static let uint = RayoType.scalar(.uint)
    public static let bool = RayoType.scalar(.bool)

    public var description: String {
        switch self {
        case .scalar(let scalar): scalar.name
        case .void: "Void"
        case .structure(let id): id.name
        case .array(let count, let element): "[\(count) of \(element)]"
        }
    }

    /// Whether the type is an integer type, which arithmetic and orderings take.
    public var isInteger: Bool {
        if case .scalar(let scalar) = self { scalar.isInteger } else { false }
    }
}
