import RayoSyntax

/// Where a run of a block can go, worked out from its syntax alone, so a statement that fails to check still counts
/// for what it does.
extension Block {
    /// Whether a run can reach the block's end.
    var canComplete: Bool {
        statements.allSatisfy(\.canComplete)
    }

    /// Whether a `break` in the block, outside any loop nested in it, leaves the loop the block belongs to.
    var breaks: Bool {
        statements.contains(where: \.breaks)
    }
}

private extension Stmt {
    /// Whether a run can go on past the statement.
    var canComplete: Bool {
        switch kind {
        // A `return`, a `break` and a `continue` go elsewhere.
        case .returnStmt, .breakStmt, .continueStmt:
            return false

        // An `if` with an `else` completes when either branch does.
        case .ifStmt(let ifExpr):
            // One without an `else` completes where its condition fails.
            guard let otherwise = ifExpr.otherwise else { return true }
            return ifExpr.then.canComplete || otherwise.canComplete

        // A loop completes once its condition fails.
        case .whileStmt(let condition, let body):
            // A `while true` that no `break` leaves never completes.
            if case .boolLiteral(true) = condition.kind { return body.breaks }
            return true

        // Every other statement goes on.
        default:
            return true
        }
    }

    /// Whether a `break` in the statement, outside any loop nested in it, leaves the loop the statement belongs to.
    var breaks: Bool {
        switch kind {
        // A `break` leaves the loop.
        case .breakStmt: true
        // So does one in a branch of an `if`, or of an `if` among a statement's values.
        case .ifStmt(let ifExpr): ifExpr.breaks
        case .declaration(_, let bindings): bindings.contains { $0.value?.breaks == true }
        case .assign(let target, _, let value): target.breaks || value.breaks
        case .drop(let value), .expression(let value), .returnStmt(let value?): value.breaks
        // A loop's condition runs outside the loop, but a `break` in its body leaves the nested loop.
        case .whileStmt(let condition, _): condition.breaks
        // Nothing else leaves a loop.
        case .continueStmt, .returnStmt(nil): false
        }
    }
}

private extension IfExpr {
    /// Whether a `break` in the `if`, outside any loop nested in it, leaves the loop the `if` belongs to.
    var breaks: Bool {
        condition.breaks || then.breaks || otherwise?.breaks == true
    }
}

private extension Expr {
    /// Whether a `break` in a branch of an `if` inside the expression leaves the loop the expression belongs to.
    var breaks: Bool {
        switch kind {
        case .if(let ifExpr): ifExpr.breaks
        case .unary(_, let operand): operand.breaks
        case .binary(_, let left, let right): left.breaks || right.breaks
        case .call(_, _, let arguments): arguments.contains { $0.value.breaks }
        case .member(let base, _, _), .copy(let base): base.breaks
        case .intLiteral, .negativeIntLiteral, .boolLiteral, .name: false
        }
    }
}
