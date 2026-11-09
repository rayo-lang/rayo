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
            case .breakStmt:
                return true
            case .ifStmt(_, let then, let otherwise):
                return then.breaks || otherwise?.breaks == true
            default:
                return false
            }
        }
    }
}

extension Stmt {
    /// Whether a run can go on past the statement. A `while true` that no `break` leaves never completes, and
    /// neither do `return`, `break` and `continue`, which go elsewhere.
    fileprivate var canComplete: Bool {
        switch kind {
        case .returnStmt, .breakStmt, .continueStmt:
            return false
        case .ifStmt(_, let then, let otherwise?):
            return then.canComplete || otherwise.canComplete
        case .whileStmt(let condition, let body):
            if case .boolLiteral(true) = condition.kind { return body.breaks }
            return true
        default:
            return true
        }
    }
}
