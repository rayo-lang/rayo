import RayoSema
import RayoSource
import RayoSyntax

/// Rayo IR: a checked program as a control-flow graph of basic blocks over numbered locals, which code
/// generation works from.
public struct IRProgram: Sendable {
    /// The program's functions, indexed by `FunctionID`.
    public var functions: [IRFunction]
    public var main: FunctionID

    public init(functions: [IRFunction], main: FunctionID) {
        self.functions = functions
        self.main = main
    }
}

public struct IRFunction: Sendable {
    /// The function's name and parameters, such as `f()`, which no other function of the program has.
    public var name: String
    /// How many parameters the function takes, which are its first locals, in order.
    public var parameterCount: Int
    public var result: RayoType
    /// The locals, indexed by `LocalID`: the function's own locals first, then the temporaries that lowering
    /// adds.
    public var locals: [IRLocal]
    /// The blocks, indexed by `BlockID`; the first is the entry.
    public var blocks: [BasicBlock]

    public init(name: String, parameterCount: Int, result: RayoType, locals: [IRLocal], blocks: [BasicBlock]) {
        self.name = name
        self.parameterCount = parameterCount
        self.result = result
        self.locals = locals
        self.blocks = blocks
    }
}

public struct IRLocal: Sendable {
    public var type: RayoType
    /// The name the source declares the local with, or nil for a temporary that lowering adds.
    public var name: String?
    /// Whether the source declares the local with `let`, which assigns it at most once on each path.
    public var isLet: Bool

    public init(type: RayoType, name: String?, isLet: Bool) {
        self.type = type
        self.name = name
        self.isLet = isLet
    }
}

public struct BlockID: Hashable, Sendable {
    public var index: Int

    public init(index: Int) {
        self.index = index
    }
}

public struct BasicBlock: Sendable {
    public var statements: [Statement]
    public var terminator: Terminator

    public init(statements: [Statement], terminator: Terminator) {
        self.statements = statements
        self.terminator = terminator
    }
}

public enum Statement: Sendable {
    /// Computes `value`, and stores it in `destination` when there is one. `range` is the source of the
    /// operation, where it reports a panic.
    case compute(destination: Place?, value: Rvalue, range: SourceRange)
    /// Starts the life of a local where the source declares it. The local holds no value until a statement
    /// stores one, whatever an earlier pass of a loop stored in it.
    case declare(LocalID)
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
    /// Reads the local's value, which the local keeps.
    case read(Place)
    /// Takes the local's value, which leaves the local without one until it is assigned again.
    case move(Place)
}

/// A local that an operand or a statement's destination names, and where the source names it, which is where an
/// error about it points.
public struct Place: Sendable {
    public var local: LocalID
    public var range: SourceRange

    public init(local: LocalID, range: SourceRange) {
        self.local = local
        self.range = range
    }
}

/// An operation that makes a value. Integer arithmetic panics on division or remainder by zero, and on
/// overflow where overflow is checked; where it isn't, overflow wraps.
public enum Rvalue: Sendable {
    case use(Operand)
    case unary(UnaryOperator, Operand)
    /// Any binary operator but `&&` and `||`, which lowering turns into branches.
    case binary(BinaryOperator, Operand, Operand)
    case call(Callee, arguments: [Operand])

    /// The operands, in the order the operation evaluates them.
    public var operands: [Operand] {
        switch self {
        case .use(let operand), .unary(_, let operand): return [operand]
        case .binary(_, let left, let right): return [left, right]
        case .call(_, let arguments): return arguments
        }
    }
}

public enum Terminator: Sendable {
    case goto(BlockID)
    /// Continues in `then` when the Bool `condition` is true, and in `otherwise` when it is false.
    case branch(Operand, then: BlockID, otherwise: BlockID)
    /// Leaves the function with the operand as its result, or with none when the function returns Void.
    case `return`(Operand?)
    /// Ends a block that no path reaches, such as the end of a function every path through which returns.
    case unreachable

    public var operand: Operand? {
        switch self {
        case .branch(let condition, _, _): return condition
        case .return(let result): return result
        case .goto, .unreachable: return nil
        }
    }

    /// The blocks that a run can continue in.
    public var successors: [BlockID] {
        switch self {
        case .goto(let target): return [target]
        case .branch(_, let then, let otherwise): return [then, otherwise]
        case .return, .unreachable: return []
        }
    }
}
