import RayoSema
import RayoSource

public enum Operand: Equatable, Sendable {
    case constant(Constant)
    /// Reads the value of the place, which keeps it, where the source names the place at the range.
    case read(Place, at: SourceRange)
    /// Takes the value of the place, which leaves it without one until it is assigned again, where the source names
    /// the place at the range.
    case move(Place, at: SourceRange)
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
