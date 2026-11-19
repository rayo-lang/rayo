import RayoSource

public enum CheckedStmt: Sendable {
    /// Computes the value and drops it.
    case expression(CheckedExpr)
    /// A declaration of the local, which the source names at the range. It gives the new local its first value, or
    /// leaves it without one until it is assigned.
    case binding(LocalID, at: SourceRange, CheckedExpr?)
    case assign(CheckedPlace, CheckedExpr)
    case compoundAssign(CheckedPlace, CheckedBinaryOperator, CheckedExpr)
    /// Runs the body for as long as the condition holds. Where the condition always holds, the loop never ends by
    /// testing it, so only a `break` leaves the loop.
    case whileStmt(condition: CheckedExpr, alwaysHolds: Bool, body: [CheckedStmt])
    case breakStmt
    case continueStmt
    /// Evaluates the value, when there is one, and leaves the function with it as the result.
    case returnStmt(CheckedExpr?)
}
