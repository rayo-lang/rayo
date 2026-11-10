import RayoSource
import RayoSyntax

public enum CheckedStmt: Sendable {
    /// Computes the value and drops it.
    case expression(CheckedExpr)
    /// A declaration, which gives the new local its first value, or leaves it without one until it is assigned.
    case binding(CheckedPlace, CheckedExpr?)
    case assign(CheckedPlace, CheckedExpr)
    case compoundAssign(CheckedPlace, BinaryOperator, CheckedExpr)
    case ifStmt(condition: CheckedExpr, then: [CheckedStmt], otherwise: [CheckedStmt])
    case whileStmt(condition: CheckedExpr, body: [CheckedStmt])
    case breakStmt
    case continueStmt
    /// Evaluates the value, when there is one, and leaves the function with it as the result.
    case returnStmt(CheckedExpr?)
}

/// A place that a statement writes, and where the source names it.
public struct CheckedPlace: Sendable {
    public var local: LocalID
    public var range: SourceRange
}
