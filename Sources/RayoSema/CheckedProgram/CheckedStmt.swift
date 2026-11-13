import RayoSource
import RayoSyntax

public enum CheckedStmt: Sendable {
    /// Computes the value and drops it.
    case expression(CheckedExpr)
    /// A declaration, which gives the new local its first value, or leaves it without one until it is assigned.
    case binding(CheckedPlace, CheckedExpr?)
    case assign(CheckedPlace, CheckedExpr)
    case compoundAssign(CheckedPlace, BinaryOperator, CheckedExpr)
    case whileStmt(condition: CheckedExpr, body: [CheckedStmt])
    case breakStmt
    case continueStmt
    /// Evaluates the value, when there is one, and leaves the function with it as the result.
    case returnStmt(CheckedExpr?)
}

/// A place that a statement writes, a local or a field inside it, and where the source names it.
public struct CheckedPlace: Sendable {
    public var local: LocalID
    /// The fields that lead from the local to the place, outermost first, each by its place in its struct's
    /// declaration; none where the place is the whole local.
    public var fields: [Int] = []
    public var range: SourceRange
}
