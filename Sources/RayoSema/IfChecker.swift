import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks an `if` used for its value: its condition, and each branch's statements and the value it ends in, which
/// stands in the `if`'s position and so settles as the `if` does.
struct IfChecker {
    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }
    private var bodyChecker: BodyChecker { BodyChecker(expressions: expressions) }

    /// Checks `ifExpr`, which the source gives at `range`, on its own: its condition, and each branch's statements,
    /// with the value each branch ends in left to wait for the `if`'s position.
    func value(of ifExpr: IfExpr, in range: SourceRange) -> IfValue? {
        let condition = expressions.check(ifExpr.condition, expecting: Expectation(.bool))
        let then = branch(ifExpr.then)

        // An `if` without an `else` has no value to give where its condition fails, which is reported after the
        // errors in `then`.
        guard let otherwiseBlock = ifExpr.otherwise else {
            expressions.reportSettlingErrors(of: [then?.value])
            errors.report(.valueIfWithoutElse, at: range)
            return nil
        }
        let otherwise = branch(otherwiseBlock)

        // A condition or a branch that failed was reported, and the other branch's value is settled for its own
        // errors.
        guard let condition, let then, let otherwise else {
            expressions.reportSettlingErrors(of: [then?.value, otherwise?.value])
            return nil
        }
        return IfValue(condition: condition, then: then, otherwise: otherwise, range: range)
    }

    /// Checks `block` as a branch of an `if` used for its value, leaving the value it ends in unsettled.
    private func branch(_ block: Block) -> IfValue.Branch? {
        // A branch that no run gets through gives no value; it is checked as a statement's branch.
        guard Reachability.canComplete(block) else {
            return IfValue.Branch(statements: bodyChecker.check(block), end: .leaves)
        }

        // The branch's statements and its value share a scope of their own.
        expressions.names.enterBlock()
        defer { expressions.names.leaveBlock() }

        // A branch that ends in an expression gives its value.
        if let last = block.lastExpression {
            let statements = bodyChecker.check(block.statements.dropLast())
            return expressions.value(of: last).map { IfValue.Branch(statements: statements, end: .value($0)) }
        }

        // A branch that ends in another statement, or holds none, gives Void.
        let statements = bodyChecker.check(block.statements[...])
        let end = block.statements.last?.range ?? block.closingBrace
        return IfValue.Branch(statements: statements, end: .void(at: end))
    }

    /// Settles `value` toward `type`: to `type` where every branch fits it, and otherwise to the one type its
    /// branches agree on, reporting each branch of another type. Reports an `if` whose branches give no type.
    func settled(_ value: IfValue, toward type: RayoType?) -> CheckedExpr? {
        if let type, value.fits(type, in: expressions.file.declarations) {
            return settled(value, expecting: Expectation(type))
        }
        guard let agreed = value.defaultType else { return reportNoType(of: value) }
        return settled(value, expecting: Expectation(agreed, mismatch: ErrorCode.branchTypesDiffer))
    }

    /// Settles each branch of `value` to the type `expected` names, reporting each branch of another type there.
    func settled(_ value: IfValue, expecting expected: Expectation) -> CheckedExpr? {
        // Both branches settle, so each one's errors are reported, before either failure fails the `if`.
        let then = settled(value.then, expecting: expected)
        let otherwise = settled(value.otherwise, expecting: expected)
        guard let then, let otherwise else { return nil }
        let kind = CheckedExprKind.if(condition: value.condition, then: then, otherwise: otherwise)
        return CheckedExpr(kind: kind, type: expected.type, range: value.range)
    }

    /// Settles `branch`'s end to the type `expected` names.
    private func settled(_ branch: IfValue.Branch, expecting expected: Expectation) -> CheckedBranch? {
        switch branch.end {
        // A value settles to the type, or reports its mismatch.
        case .value(let value):
            expressions.settled(value, expecting: expected).map {
                CheckedBranch(statements: branch.statements, value: $0)
            }

        // A Void branch's mismatch is reported at its end.
        case .void(let end):
            expressions.fits(.void, at: end, expected) ? CheckedBranch(statements: branch.statements, value: nil) : nil

        // A branch that no run gets through fits any type.
        case .leaves:
            CheckedBranch(statements: branch.statements, value: nil)
        }
    }

    /// Reports `value`, whose branches give no type, and returns nil. Where every branch leaves, the `if` has no
    /// value; otherwise each branch's value is settled with no type, which reports why it has none, as `[]` does.
    private func reportNoType(of value: IfValue) -> CheckedExpr? {
        let values = value.branches.compactMap(\.value)
        if values.isEmpty { errors.report(.valueIfLeavesEveryBranch, at: value.range) }
        for branchValue in values { _ = expressions.settled(branchValue, toward: nil) }
        return nil
    }
}
