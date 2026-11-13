import RayoSema
import RayoSource

public enum Statement: Equatable, Sendable {
    /// Computes `value`, and stores it in `destination` when there is one. `range` is the source of the
    /// operation, where it reports a panic.
    case compute(destination: Destination?, value: Rvalue, range: SourceRange)
    /// Starts the life of a local where the source declares it. The local holds no value until a statement
    /// stores one, whatever an earlier pass of a loop stored in it.
    case declare(LocalID)
}

/// An operation that makes a value. Integer arithmetic panics on division or remainder by zero, and on overflow as
/// its operator's overflow mode says.
public enum Rvalue: Equatable, Sendable {
    case use(Operand)
    case unary(IRUnaryOperator, Operand)
    case binary(IRBinaryOperator, Operand, Operand)
    case call(Callee, arguments: [Operand])
    /// Makes a value of the struct from its fields' values, in the order the struct declares its fields.
    case structure(StructID, fields: [Operand])

    /// The operands, in the order the operation evaluates them.
    public var operands: [Operand] {
        switch self {
        case .use(let operand), .unary(_, let operand): return [operand]
        case .binary(_, let left, let right): return [left, right]
        case .call(_, let arguments), .structure(_, let arguments): return arguments
        }
    }

    /// The type of the value the operation makes in `body`, a body of a program whose structs `types` holds and
    /// whose functions `functions` declares. The operation's operands must be of the types it takes.
    public func type(in body: IRBody, types: TypeTable, functions: FunctionTable) -> RayoType {
        switch self {
        case .use(let operand): operand.type(in: body, types: types)
        case .unary(let op, let operand): op.resultType(on: operand.type(in: body, types: types))
        case .binary(let op, let left, _): op.resultType(on: left.type(in: body, types: types))
        case .call(let callee, _): callee.result(in: functions)
        case .structure(let id, _): .structure(id)
        }
    }
}
