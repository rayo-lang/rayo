/// The type of a value in a checked program.
public indirect enum RayoType: Hashable, Sendable, CustomStringConvertible {
    /// A number or a truth value, one of the prelude's scalar types.
    case scalar(ScalarType)
    case void
    /// A type the program declares by name, such as a struct.
    case named(TypeID)
    /// `[count of element]`: `count` values of the element's type, which lie end to end.
    case array(count: Int, element: RayoType)

    public static let int = RayoType.scalar(.int)
    public static let uint = RayoType.scalar(.uint)
    public static let bool = RayoType.scalar(.bool)

    /// The prelude's type called `name`, a scalar type or Void, or nil where the prelude has none.
    public static func prelude(named name: String) -> RayoType? {
        if let scalar = ScalarType.named(name) { .scalar(scalar) } else if name == "Void" { .void } else { nil }
    }

    public var description: String {
        switch self {
        case .scalar(let scalar): scalar.name
        case .void: "Void"
        case .named(let id): id.name
        case .array(let count, let element): "[\(count) of \(element)]"
        }
    }

    /// Whether the type is an integer type, which arithmetic and orderings take.
    public var isInteger: Bool {
        if case .scalar(let scalar) = self { scalar.isInteger } else { false }
    }

    /// Whether the type's values carry a sign, as a signed integer type's do.
    public var isSigned: Bool {
        if case .scalar(let scalar) = self { scalar.isSigned } else { false }
    }

    /// Whether the type is implicitly copyable: a value of it that a position takes from a place is copied, and the
    /// place keeps its value, with no `copy` written. A scalar type is. An array never is, and a struct is only by
    /// listing the conformance, which a struct declaration can't, so no struct is.
    public var isImplicitlyCopyable: Bool {
        if case .scalar = self { true } else { false }
    }
}
