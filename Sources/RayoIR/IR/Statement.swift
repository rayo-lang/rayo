import RayoSema
import RayoSource

/// One step of a basic block, run in order with the block's other statements.
public enum Statement: Equatable, Sendable {
    /// Computes a value, and stores it in the destination, or drops it where there is none. The range is the source
    /// of the operation, where a panic in it is reported.
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

/// The operation a statement makes its value with, from its operands.
public enum Rvalue: Equatable, Sendable {
    /// The operand's value as it is, with no operation applied: a constant, or the value read or moved out of a
    /// place.
    case operand(Operand)
    /// An operator applied to one operand, such as negation.
    case unary(IRUnaryOperator, Operand)
    /// An operator applied to two operands, such as addition or a comparison.
    case binary(IRBinaryOperator, Operand, Operand)
    /// A call of a function, whose value is the function's result.
    case call(Callee, arguments: [CallArgument])
    /// An array of the operands' values, in order, each of the element type, which the array takes as its own.
    case array([Operand], of: RayoType)

    /// The operands, in the order the operation evaluates them. A call argument that passes an access, rather than a
    /// value, isn't an operand.
    public var operands: [Operand] {
        switch self {
        case .operand(let operand), .unary(_, let operand): [operand]
        case .binary(_, let left, let right): [left, right]
        case .call(_, let arguments): arguments.compactMap(\.operand)
        case .array(let elements, _): elements
        }
    }

    /// The accesses a call passes, in the order of its arguments; none for any other operation.
    public var accesses: [AccessID] {
        guard case .call(_, let arguments) = self else { return [] }
        return arguments.compactMap(\.access)
    }

    /// The type of the value the operation makes, in the given body of a program with the given structs and
    /// functions. The operands must have the types the operation takes.
    public func type(in body: IRBody, types: TypeTable, functions: FunctionTable) -> RayoType {
        switch self {
        case .operand(let operand): operand.type(in: body, types: types)
        case .unary(let op, let operand): op.resultType(on: operand.type(in: body, types: types))
        case .binary(let op, let left, _): op.resultType(on: left.type(in: body, types: types))
        case .call(let callee, _): callee.result(in: functions)
        case .array(let elements, let element): .array(count: elements.count, element: element)
        }
    }
}
