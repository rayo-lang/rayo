import RayoSyntax

/// Which ends of a body a run can reach, worked out from its syntax alone, so a statement that fails to check
/// still counts for what it does.
extension Block {
    /// Whether a run can reach the block's end: every statement in it can complete.
    var canComplete: Bool {
        statements.allSatisfy(\.canComplete)
    }

    /// Whether a `break` in the block, outside any loop nested in it, leaves the loop the block belongs to.
    fileprivate var breaks: Bool {
        statements.contains { statement in
            switch statement.kind {
            // A `break` leaves the loop.
            case .breakStmt:
                return true

            // An `if` leaves the loop when either of its branches does.
            case .ifStmt(_, let then, let otherwise):
                return then.breaks || otherwise?.breaks == true

            // A `break` in a nested loop leaves only that loop, and no other statement leaves one.
            default:
                return false
            }
        }
    }
}

extension Stmt {
    /// Whether a run can go on past the statement.
    fileprivate var canComplete: Bool {
        switch kind {
        // `return`, `break` and `continue` go elsewhere.
        case .returnStmt, .breakStmt, .continueStmt:
            return false

        // An `if` with an `else` completes when either branch does.
        case .ifStmt(_, let then, let otherwise?):
            return then.canComplete || otherwise.canComplete

        // A loop completes when its condition turns false, or a `break` leaves it.
        case .whileStmt(let condition, let body):
            // A `while true` never stops at its condition, so only a `break` gets past it.
            if case .boolLiteral(true) = condition.kind { return body.breaks }
            return true

        // An `if` without an `else`, and every other statement, completes.
        default:
            return true
        }
    }
}
