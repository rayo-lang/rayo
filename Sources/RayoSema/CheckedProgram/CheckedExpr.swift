import RayoSource
import RayoSyntax

public struct CheckedExpr: Sendable {
    public var kind: CheckedExprKind
    public var type: RayoType
    public var range: SourceRange
}

public indirect enum CheckedExprKind: Sendable {
    case intLiteral(Int64)
    case boolLiteral(Bool)
    /// Reads the local's value, which the local keeps.
    case local(LocalID)
    /// Takes the value of a place: a local, or a field read through a local or a temporary, which leaves the place
    /// without one until it is assigned again.
    case move(CheckedExpr)
    case unary(UnaryOperator, CheckedExpr)
    case binary(BinaryOperator, CheckedExpr, CheckedExpr)
    case call(Callee, arguments: [CheckedExpr])
    /// Makes a value of the struct from its fields' values, in the order the struct declares its fields.
    case structure(StructID, fields: [CheckedExpr])
    /// Reads a field of the struct value, which keeps it. `index` is the field's place in the struct's declaration.
    case field(CheckedExpr, index: Int)
    /// Runs `then` when the Bool `condition` is true, and `otherwise` when it is false, and gives the value of the
    /// branch that runs.
    case `if`(condition: CheckedExpr, then: CheckedBranch, otherwise: CheckedBranch)
}

/// A branch of an `if`: the statements it runs, then the value it ends in.
public struct CheckedBranch: Sendable {
    public var statements: [CheckedStmt]
    /// The value the `if` gives when the branch runs; nil where the branch gives none, since the `if` is a statement,
    /// or the branch is Void and ends in a statement, or no run reaches its end.
    public var value: CheckedExpr?
}
