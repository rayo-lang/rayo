import RayoSema
import RayoSyntax

/// Rayo IR: a checked program as a control-flow graph of basic blocks over numbered locals, which code
/// generation works from.
public struct IRProgram: Sendable {
    public var main: IRFunction
}

public struct IRFunction: Sendable {
    /// The type of each local, indexed by `LocalID`.
    public var locals: [RayoType]
    /// The blocks, indexed by `BlockID`; the first is the entry.
    public var blocks: [BasicBlock]
}

public struct LocalID: Hashable, Sendable {
    public var index: Int
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

public enum Operand: Sendable {
    case constant(Int64)
    /// Reads the local's value.
    case local(LocalID)
}

/// An operation that makes a value. Integer arithmetic panics on overflow, and on division or remainder
/// by zero.
public enum Rvalue: Sendable {
    case use(Operand)
    case unary(UnaryOperator, Operand)
    case binary(BinaryOperator, Operand, Operand)
    case call(Callee, arguments: [Operand])
}

public enum Terminator: Sendable {
    case `return`
}
