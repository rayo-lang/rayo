import RayoCheckedProgram
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
            expressions.reportSettlingErrors(of: [then?.end.value])
            errors.report(.valueIfWithoutElse, at: range)
            return nil
        }
        let otherwise = branch(otherwiseBlock)

        // A condition or a branch that failed was reported, and the other branch's value is settled for its own
        // errors.
        guard let condition, let then, let otherwise else {
            expressions.reportSettlingErrors(of: [then?.end.value, otherwise?.end.value])
            return nil
        }
        let declarations = expressions.file.declarations
        return IfValue(condition: condition, then: then, otherwise: otherwise, range: range, in: declarations)
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

    /// Settles `value` toward `type`: to `type` where every branch fits it, and otherwise to the type the one rule
    /// for values side by side picks for its branches, reporting each branch of another type. Each branch's value is
    /// taken by `recipient`, where the `if`'s position has one. Reports an `if` whose branches give no type.
    func settled(_ value: IfValue, toward type: RayoType?, takenBy recipient: Recipient?) -> CheckedExpr? {
        if let type, value.fits(type, in: expressions.file.declarations) {
            return settled(value, expecting: Expectation(type, recipient: recipient))
        }
        guard let ruled = value.ruledType else { return reportNoType(of: value) }
        let expected = Expectation(ruled, recipient: recipient, mismatch: ErrorCode.branchTypesDiffer)
        return settled(value, expecting: expected)
    }

    /// Settles each branch of `value` to the type `expected` names, reporting each branch of another type there.
    func settled(_ value: IfValue, expecting expected: Expectation) -> CheckedExpr? {
        // A parameter that borrows its argument for change takes a place, which an `if` is not: its branches settle
        // as a value's do, and the value it gives is a temporary.
        if let parameter = expected.recipient?.mutableParameter {
            let valueExpected = Expectation(expected.type, mismatch: expected.mismatch)
            return settled(value, expecting: valueExpected).flatMap { expressions.unmarkedLend(of: $0, to: parameter) }
        }

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

        case .void(let end):
            voidBranch(of: branch.statements, endingAt: end, expecting: expected)

        // A branch that no run gets through fits any type.
        case .leaves:
            CheckedBranch(statements: branch.statements, value: nil)
        }
    }

    /// The branch of `statements` that gives Void, where the type `expected` names takes Void. Reports the mismatch
    /// at `end`, where the branch ends, when it doesn't.
    private func voidBranch(of statements: [CheckedStmt], endingAt end: SourceRange,
                            expecting expected: Expectation) -> CheckedBranch? {
        guard expressions.fits(.void, at: end, expected) else { return nil }
        return CheckedBranch(statements: statements, value: nil)
    }

    /// Reports `value`, whose branches give no type, and returns nil. Where every branch leaves, the `if` has no
    /// value; otherwise each branch's value is settled with no type, which reports why it has none, as `[]` does.
    private func reportNoType(of value: IfValue) -> CheckedExpr? {
        let values = value.ends.compactMap(\.value)
        if values.isEmpty { errors.report(.valueIfLeavesEveryBranch, at: value.range) }
        for branchValue in values { _ = expressions.settled(branchValue, toward: nil) }
        return nil
    }
}
