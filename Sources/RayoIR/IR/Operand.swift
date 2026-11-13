import RayoSema
import RayoSource

public enum Operand: Equatable, Sendable {
    case constant(Constant)
    /// Reads the value of the place, which keeps it, where the source names the place at the range.
    case read(Place, at: SourceRange)
    /// Takes the value of the place, which leaves it without one until it is assigned again, where the source names
    /// the place at the range.
    case move(Place, at: SourceRange)

    /// The type of the operand's value in `body`, a body of a program whose structs `types` holds. A place the
    /// operand names must step only into fields its values have.
    public func type(in body: IRBody, types: TypeTable) -> RayoType {
        switch self {
        // A constant's value is of the constant's type.
        case .constant(let constant):
            return constant.type

        // A place's value is of the type its steps lead to, which, in IR that keeps its types, they always do.
        case .read(let place, _), .move(let place, _):
            do {
                return try place.type(in: body, types: types)
            } catch {
                preconditionFailure("the IR names \(error.step) of a value of type \(error.holder)")
            }
        }
    }
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
