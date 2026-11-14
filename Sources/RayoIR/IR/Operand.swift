import RayoSema
import RayoSource

/// An input to an operation: a constant, or the value at a place, either read or moved out.
public enum Operand: Equatable, Sendable {
    case constant(Constant)
    /// Reads the value at the place, which keeps it. The range is where the source names the place.
    case read(Place, at: SourceRange)
    /// Moves the value out of the place, a local or a field of one, which then holds no value until it is assigned
    /// again. The range is where the source names the place.
    case move(Place, at: SourceRange)

    /// The place the operand reads or moves, or nil for a constant.
    public var place: Place? {
        switch self {
        case .read(let place, _), .move(let place, _): place
        case .constant: nil
        }
    }

    /// The type of the operand's value, in the given body of a program with the given structs. A place the operand
    /// names must lead only into fields that exist.
    public func type(in body: IRBody, types: TypeTable) -> RayoType {
        switch self {
        case .constant(let constant): constant.type
        case .read(let place, _), .move(let place, _): Self.type(of: place, in: body, types: types)
        }
    }

    /// The type of the value at a place, in the given body of a program with the given structs. Each step into a
    /// field must name a field that the struct it steps from has.
    private static func type(of place: Place, in body: IRBody, types: TypeTable) -> RayoType {
        do {
            return try place.type(in: body, types: types)
        } catch {
            // IR that keeps its types steps only into fields its values have.
            preconditionFailure("the IR names \(error.step) of a value of type \(error.holder)")
        }
    }
}

/// A value written into the IR itself, an integer or a Boolean, as a literal in the source gives it.
public enum Constant: Equatable, Sendable {
    case int(Int64)
    case uint(UInt64)
    case bool(Bool)

    public var type: RayoType {
        switch self {
        case .int: .int
        case .uint: .uint
        case .bool: .bool
        }
    }
}
