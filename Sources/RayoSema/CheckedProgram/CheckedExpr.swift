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
    /// Takes the local's value, which leaves the local without one until it is assigned again.
    case move(LocalID)
    case unary(UnaryOperator, CheckedExpr)
    case binary(BinaryOperator, CheckedExpr, CheckedExpr)
    case call(Callee, arguments: [CheckedExpr])
}
