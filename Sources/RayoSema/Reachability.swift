import RayoSource
import RayoSyntax

/// Where a run of a function body can go, worked out from its syntax alone, so a statement that fails to check still
/// counts for what it does. Only the forms that change where a run goes are told apart; every other form completes,
/// and leaves a loop, as its parts do. It keeps whether a run gets past each `if` it has worked out.
final class Reachability {
    /// Whether a run can go on past each `if` worked out so far, by its condition's range, which no two `if`s share.
    /// Each `if` whose branch is checked for its value asks about the `if`s nested in it, so each is worked out once.
    private var completesPastIf: [SourceRange: Bool] = [:]

    /// Whether a run can reach the end of `block`.
    func canComplete(_ block: Block) -> Bool {
        block.statements.allSatisfy(canComplete)
    }

    /// Whether `condition`, a loop's condition, is true on every test and has no effect of its own, so that only a
    /// `break` leaves the loop. Only the literal `true` is taken to hold always.
    static func alwaysHolds(_ condition: Expr) -> Bool {
        if case .boolLiteral(true) = condition.kind { true } else { false }
    }

    /// Whether a run can go on past `statement`.
    private func canComplete(_ statement: Stmt) -> Bool {
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

        // A loop completes once its condition fails, and one whose condition always holds only where a `break` leaves
        // it.
        case .whileStmt(let condition, let body):
            if Self.alwaysHolds(condition) { return Self.breaks(body) }
            return canComplete(condition)

        // Any other statement completes once the values it evaluates do.
        default:
            return statement.children.allSatisfy(canComplete)
        }
    }

    /// Whether a run can go on past `ifExpr`.
    private func canComplete(_ ifExpr: IfExpr) -> Bool {
        if let completes = completesPastIf[ifExpr.condition.range] { return completes }
        let completes = canCompleteFromParts(ifExpr)
        completesPastIf[ifExpr.condition.range] = completes
        return completes
    }

    /// Whether a run can go on past `ifExpr`, worked out from its parts.
    private func canCompleteFromParts(_ ifExpr: IfExpr) -> Bool {
        // A condition that can't complete leaves before either branch runs.
        guard canComplete(ifExpr.condition) else { return false }
        // Without an `else`, a run goes on where the condition fails.
        guard let otherwise = ifExpr.otherwise else { return true }
        return canComplete(ifExpr.then) || canComplete(otherwise)
    }

    /// Whether a run can go on past `expr`, which it can't where an `if` it evaluates can't.
    private func canComplete(_ expr: Expr) -> Bool {
        switch expr.kind {
        // An `if` completes when a run gets through it.
        case .if(let ifExpr): canComplete(ifExpr)
        // `&&` and `||` evaluate their right operand on some runs only, so their left operand decides.
        case .binary(.and, let left, _), .binary(.or, let left, _): canComplete(left)
        // Every other expression evaluates each of its operands.
        default: expr.children.allSatisfy(canComplete)
        }
    }

    /// Whether a run can go on past `child`, a part of a statement or an expression that evaluates it whole.
    private func canComplete(_ child: SyntaxChild) -> Bool {
        switch child {
        case .expression(let expr): canComplete(expr)
        case .block(let block): canComplete(block)
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
        // A loop's condition runs outside the loop, but a `break` in its body leaves the nested loop.
        case .whileStmt(let condition, _): breaks(condition)
        // Any other statement leaves the loop where one of its parts does. A statement that failed to parse has none,
        // so it is taken to leave no loop, the loop isn't taken to complete, and no missing `return` is reported
        // after it.
        default: statement.children.contains(where: breaks)
        }
    }

    /// Whether a `break` in a branch of an `if` inside `expr` leaves the loop the expression belongs to.
    private static func breaks(_ expr: Expr) -> Bool {
        expr.children.contains(where: breaks)
    }

    /// Whether a `break` in `child`, outside any loop nested in it, leaves the loop the child belongs to.
    private static func breaks(_ child: SyntaxChild) -> Bool {
        switch child {
        case .expression(let expr): breaks(expr)
        case .block(let block): breaks(block)
        }
    }
}
