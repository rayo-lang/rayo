import RayoSema
import RayoSyntax

/// Rayo IR: a checked program as a control-flow graph of basic blocks over numbered locals, which code
/// generation works from.
public struct IRProgram: Sendable {
    public var main: IRFunction
}

public struct IRFunction: Sendable {
    /// The type of each local, indexed by `LocalID`: the function's own locals first, then the temporaries
    /// that lowering adds.
    public var locals: [RayoType]
    /// The blocks, indexed by `BlockID`; the first is the entry.
    public var blocks: [BasicBlock]
}

public struct BlockID: Hashable, Sendable {
    public var index: Int
}

public struct BasicBlock: Sendable {
    public var statements: [Statement]
    public var terminator: Terminator
}

/// Computes `value`, and stores it in `destination` when there is one.
public struct Statement: Sendable {
    public var destination: LocalID?
    public var value: Rvalue
    /// The source of the operation, where it reports a panic.
    public var range: SourceRange
}

public enum Constant: Sendable {
    case int(Int64)
    case bool(Bool)

    public var type: RayoType {
        switch self {
        case .int: return .int
        case .bool: return .bool
        }
    }
}

public enum Operand: Sendable {
    case constant(Constant)
    /// Reads the local's value.
    case local(LocalID)
}

/// An operation that makes a value. Integer arithmetic panics on division or remainder by zero, and on
/// overflow where overflow is checked; where it isn't, overflow wraps.
public enum Rvalue: Sendable {
    case use(Operand)
    case unary(UnaryOperator, Operand)
    /// Any binary operator but `&&` and `||`, which lowering turns into branches.
    case binary(BinaryOperator, Operand, Operand)
    case call(Callee, arguments: [Operand])
}

public enum Terminator: Sendable {
    case goto(BlockID)
    /// Continues in `then` when the Bool `condition` is true, and in `otherwise` when it is false.
    case branch(Operand, then: BlockID, otherwise: BlockID)
    case `return`
}
