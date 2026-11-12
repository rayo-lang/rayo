import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks an `if` used for its value: its condition, and each branch's statements and the value it ends in, which
/// stands in the `if`'s position.
struct IfChecker {
    /// A checked branch, and the type of its value; nil where no run reaches the branch's end, so it fits any type.
    private typealias Branch = (checked: CheckedBranch, type: RayoType?)

    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }
    private var bodyChecker: BodyChecker { BodyChecker(expressions: expressions) }

    /// Checks `ifExpr`, which the source gives at `range`, as the value of a position that `use`s it, and that expects
    /// `expected` of it where it expects a type.
    func check(_ ifExpr: IfExpr, in range: SourceRange, as use: ValueUse,
               expecting expected: Expectation?) -> CheckedExpr? {
        // Check the condition, and `then` as the position's own value.
        let condition = expressions.check(ifExpr.condition, expecting: .bool)
        let then = branch(ifExpr.then, as: use, expecting: expected)

        // An `if` without an `else` has no value to give where its condition fails, which is reported.
        guard let otherwiseBlock = ifExpr.otherwise else {
            errors.report(.valueIfWithoutElse, at: range)
            return nil
        }
        // Where the position expects no type, the `else` must give the type that `then` gives.
        let otherwise = branch(otherwiseBlock, as: use, expecting: expected ?? agreeing(with: then))

        // A condition or a branch that failed was reported.
        guard let condition, let then, let otherwise else { return nil }
        // The `if` has the type its position expects, or else the one its branches give. Where neither branch gives
        // one, since no run gets through either, and the position expects none, the `if` has no type, which is
        // reported.
        guard let type = expected?.type ?? then.type ?? otherwise.type else {
            errors.report(.valueIfLeavesEveryBranch, at: range)
            return nil
        }
        let kind = CheckedExprKind.if(condition: condition, then: then.checked, otherwise: otherwise.checked)
        return CheckedExpr(kind: kind, type: type, range: range)
    }

    /// What the branches after `first` must give, where the position expects no type: the type that `first` gives.
    private func agreeing(with first: Branch?) -> Expectation? {
        // A branch that failed, or that no run gets through, gives no type to agree with.
        guard let type = first?.type else { return nil }
        return Expectation(type, mismatch: ErrorCode.branchTypesDiffer)
    }

    /// Checks `block` as a branch whose value stands in the position of the `if`, which `use`s it, and expects
    /// `expected` of it where it expects a type.
    private func branch(_ block: Block, as use: ValueUse, expecting expected: Expectation?) -> Branch? {
        // A branch that no run gets through gives no value, and fits any type; it is checked as a statement's branch.
        guard Reachability.canComplete(block) else {
            return (CheckedBranch(statements: bodyChecker.check(block), value: nil), nil)
        }

        // The branch's statements and its value share a scope of their own.
        expressions.names.enterBlock()
        defer { expressions.names.leaveBlock() }

        // A branch that ends in an expression gives its value.
        if let last = block.lastExpression {
            let checked = bodyChecker.check(block.statements.dropLast())
            let value = expressions.check(last, as: use, expecting: expected)
            return value.map { (CheckedBranch(statements: checked, value: $0), $0.type) }
        }

        // A branch that ends in another statement, or holds none, gives Void, which the position must expect.
        let checked = bodyChecker.check(block.statements[...])
        let end = block.statements.last?.range ?? block.closingBrace
        // A position that expects another type was reported at the branch's end.
        if let expected, !expressions.expect(.void, at: end, expected) { return nil }
        return (CheckedBranch(statements: checked, value: nil), .void)
    }
}
