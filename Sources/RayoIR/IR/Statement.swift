import RayoSema
import RayoSource
import RayoSyntax

public enum Statement: Equatable, Sendable {
    /// Computes `value`, and stores it in `destination` when there is one. `range` is the source of the
    /// operation, where it reports a panic.
    case compute(destination: Place?, value: Rvalue, range: SourceRange)
    /// Starts the life of a local where the source declares it. The local holds no value until a statement
    /// stores one, whatever an earlier pass of a loop stored in it.
    case declare(LocalID)
}

/// An operation that makes a value. Integer arithmetic panics on division or remainder by zero, and on
/// overflow where overflow is checked; where it isn't, overflow wraps.
public enum Rvalue: Equatable, Sendable {
    case use(Operand)
    case unary(UnaryOperator, Operand)
    /// Any binary operator but `&&` and `||`, which lowering turns into branches.
    case binary(BinaryOperator, Operand, Operand)
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
}
