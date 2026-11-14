import RayoSyntax

/// Where a run of a function body can go, worked out from its syntax alone, so a statement that fails to check still
/// counts for what it does.
enum Reachability {
    /// Whether a run can reach the end of `block`.
    static func canComplete(_ block: Block) -> Bool {
        block.statements.allSatisfy(canComplete)
    }

    /// Whether a run can go on past `statement`.
    private static func canComplete(_ statement: Stmt) -> Bool {
        switch statement.kind {
        // A `return`, a `break` and a `continue` go elsewhere.
        case .returnStmt, .breakStmt, .continueStmt:
            return false

        // A statement that failed to parse may have been one that goes elsewhere, so no missing `return` is reported
        // after it.
        case .error:
            return false

        // An `if` completes as it does as a value.
        case .ifStmt(let ifExpr):
            return canComplete(ifExpr)

        // A loop completes once its condition fails.
        case .whileStmt(let condition, let body):
            // A `while true` that no `break` leaves never completes.
            if case .boolLiteral(true) = condition.kind { return breaks(body) }
            return canComplete(condition)

        // Any other statement completes once the values it evaluates do.
        case .declaration(_, let bindings):
            return bindings.allSatisfy { $0.value.map(canComplete) ?? true }
        case .assign(let target, _, let value):
            return canComplete(target) && canComplete(value)
        case .drop(let value), .expression(let value):
            return canComplete(value)
        }
    }

    /// Whether a run can go on past `ifExpr`.
    private static func canComplete(_ ifExpr: IfExpr) -> Bool {
        // A condition that can't complete leaves before either branch runs.
        guard canComplete(ifExpr.condition) else { return false }
        // Without an `else`, a run goes on where the condition fails.
        guard let otherwise = ifExpr.otherwise else { return true }
        return canComplete(ifExpr.then) || canComplete(otherwise)
    }

    /// Whether a run can go on past `expr`, which it can't where an `if` it evaluates can't.
    private static func canComplete(_ expr: Expr) -> Bool {
        switch expr.kind {
        // An `if` completes when a run gets through it.
        case .if(let ifExpr): canComplete(ifExpr)
        // `&&` and `||` evaluate their right operand on some runs only, so their left operand decides.
        case .binary(.and, let left, _), .binary(.or, let left, _): canComplete(left)
        // Every other operation evaluates each of its operands.
        case .binary(_, let left, let right): canComplete(left) && canComplete(right)
        case .unary(_, let operand): canComplete(operand)
        case .call(let callee, let arguments): canComplete(callee) && arguments.allSatisfy { canComplete($0.value) }
        case .member(let base, _, _), .copy(let base): canComplete(base)
        // A literal or a name evaluates nothing.
        case .intLiteral, .negativeIntLiteral, .boolLiteral, .name, .implicitMember: true
        }
    }

    /// Whether a `break` in `block`, outside any loop nested in it, leaves the loop the block belongs to.
    private static func breaks(_ block: Block) -> Bool {
        block.statements.contains(where: breaks)
    }

    /// Whether a `break` in `statement`, outside any loop nested in it, leaves the loop the statement belongs to.
    private static func breaks(_ statement: Stmt) -> Bool {
        switch statement.kind {
        // A `break` leaves the loop.
        case .breakStmt: true
        // So does one in a branch of an `if`, or of an `if` among a statement's values.
        case .ifStmt(let ifExpr): breaks(ifExpr)
        case .declaration(_, let bindings): bindings.contains { $0.value.map(breaks) ?? false }
        case .assign(let target, _, let value): breaks(target) || breaks(value)
        case .drop(let value), .expression(let value), .returnStmt(let value?): breaks(value)
        // A loop's condition runs outside the loop, but a `break` in its body leaves the nested loop.
        case .whileStmt(let condition, _): breaks(condition)
        // Nothing else leaves a loop; a statement that failed to parse is taken to leave none, so the loop isn't
        // taken to complete, and no missing `return` is reported after it.
        case .continueStmt, .returnStmt(nil), .error: false
        }
    }

    /// Whether a `break` in `ifExpr`, outside any loop nested in it, leaves the loop the `if` belongs to.
    private static func breaks(_ ifExpr: IfExpr) -> Bool {
        breaks(ifExpr.condition) || breaks(ifExpr.then) || (ifExpr.otherwise.map(breaks) ?? false)
    }

    /// Whether a `break` in a branch of an `if` inside `expr` leaves the loop the expression belongs to.
    private static func breaks(_ expr: Expr) -> Bool {
        switch expr.kind {
        case .if(let ifExpr): breaks(ifExpr)
        case .unary(_, let operand): breaks(operand)
        case .binary(_, let left, let right): breaks(left) || breaks(right)
        case .call(let callee, let arguments): breaks(callee) || arguments.contains { breaks($0.value) }
        case .member(let base, _, _), .copy(let base): breaks(base)
        case .intLiteral, .negativeIntLiteral, .boolLiteral, .name, .implicitMember: false
        }
    }
}
