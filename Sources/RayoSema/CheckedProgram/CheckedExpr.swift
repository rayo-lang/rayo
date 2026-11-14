import RayoSource

public struct CheckedExpr: Sendable {
    public var kind: CheckedExprKind
    public var type: RayoType
    public var range: SourceRange
}

public indirect enum CheckedExprKind: Sendable {
    case intLiteral(Int64)
    case uintLiteral(UInt64)
    case boolLiteral(Bool)
    /// The value of a place that the source writes on its own. Lowering decides whether its position reads the
    /// value, or moves it out of the place.
    case place(CheckedPlace)
    /// A copy of the value of a place, which the place keeps wherever the copy is used.
    case copy(CheckedPlace)
    case unary(CheckedUnaryOperator, CheckedExpr)
    case binary(CheckedBinaryOperator, CheckedExpr, CheckedExpr)
    case call(Callee, arguments: [CheckedExpr])
    /// Runs `then` when the Bool `condition` is true, and `otherwise` when it is false, and gives the value of the
    /// branch that runs.
    case `if`(condition: CheckedExpr, then: CheckedBranch, otherwise: CheckedBranch)
    /// An array of the elements' values, each of the array's element type, evaluated from first to last and taken
    /// as the array's own.
    case arrayLiteral([CheckedExpr])
}

/// A branch of an `if`: the statements it runs, then the value it ends in.
public struct CheckedBranch: Sendable {
    public var statements: [CheckedStmt]
    /// The value the `if` gives when the branch runs. It is nil where the branch gives none:
    /// - in an `if` that is a statement
    /// - in a Void branch that ends in a statement
    /// - in a branch no run reaches the end of
    public var value: CheckedExpr?
}
