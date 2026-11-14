import RayoSema
import RayoSource

public enum Statement: Equatable, Sendable {
    /// Computes `value`, and stores it in `destination` when there is one. `range` is the source of the
    /// operation, where it reports a panic.
    case compute(destination: Destination?, value: Rvalue, range: SourceRange)
    /// Starts the life of a local where the source declares it. The local holds no value until a statement
    /// stores one, whatever an earlier pass of a loop stored in it.
    case declare(LocalID)
    /// Begins the access to a place, which the code then reaches the place through. The place is found here, once,
    /// whatever the code changes before the access ends.
    case begin(AccessID, Access)
    /// Ends the access, after which nothing reaches the place through it.
    case end(AccessID)
    /// Makes the value at the place depend on the access too, so the access stays live while the value is used.
    case depend(Place, on: AccessID)
}

/// An operation that makes a value. Integer arithmetic panics on division or remainder by zero, and on overflow as
/// its operator's overflow mode says.
public enum Rvalue: Equatable, Sendable {
    case use(Operand)
    case unary(IRUnaryOperator, Operand)
    case binary(IRBinaryOperator, Operand, Operand)
    case call(Callee, arguments: [CallArgument])

    /// The operands, in the order the operation evaluates them. A call's arguments that pass an access are none.
    public var operands: [Operand] {
        switch self {
        case .use(let operand), .unary(_, let operand): [operand]
        case .binary(_, let left, let right): [left, right]
        case .call(_, let arguments): arguments.compactMap(\.operand)
        }
    }

    /// The accesses a call passes, in the order of its arguments; none for any other operation.
    public var accesses: [AccessID] {
        guard case .call(_, let arguments) = self else { return [] }
        return arguments.compactMap(\.access)
    }

    /// The type of the value the operation makes in `body`, a body of a program whose structs `types` holds and
    /// whose functions `functions` declares. The operation's operands must be of the types it takes.
    public func type(in body: IRBody, types: TypeTable, functions: FunctionTable) -> RayoType {
        switch self {
        case .use(let operand): operand.type(in: body, types: types)
        case .unary(let op, let operand): op.resultType(on: operand.type(in: body, types: types))
        case .binary(let op, let left, _): op.resultType(on: left.type(in: body, types: types))
        case .call(let callee, _): callee.result(in: functions)
        }
    }
}
