import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a function body's statements, block by block, and the loops and returns among them.
struct BodyChecker {
    private let expressions: ExpressionChecker

    /// A checker of the body of a function whose result type is `result`, with `parameters`, whose types are
    /// `types`, as its first locals, reporting what in them can't be declared.
    init(file: FileChecker, parameters: [Param], types: [RayoType?], result: RayoType?) {
        // Give the body names of its own, which every checker it builds shares.
        self.init(expressions: ExpressionChecker(file: file, names: NameScopes(file: file),
                                                 jumps: JumpTargets(result: result)))

        // Declare the parameters in the scope around the body's blocks.
        bindingChecker.declare(parameters, types: types)
    }

    /// A checker of statements whose expressions `expressions` checks.
    init(expressions: ExpressionChecker) {
        self.expressions = expressions
    }

    /// The body's locals, indexed by `LocalID`, its parameters first.
    var locals: [CheckedLocal] { expressions.names.locals }

    private var errors: ErrorList { expressions.file.errors }
    private var jumps: JumpTargets { expressions.jumps }
    private var bindingChecker: BindingChecker { BindingChecker(expressions: expressions) }
    private var assignmentChecker: AssignmentChecker { AssignmentChecker(expressions: expressions) }

    /// Checks `block`'s statements in a scope of their own.
    func check(_ block: Block) -> [CheckedStmt] {
        expressions.names.enterBlock()
        defer { expressions.names.leaveBlock() }
        return check(block.statements[...])
    }

    /// Checks `statements` in the innermost scope, and gives the checked statements, without those that fail.
    func check(_ statements: ArraySlice<Stmt>) -> [CheckedStmt] {
        statements.flatMap { check($0) }.compactMap { $0 }
    }

    /// Checks `expr` as the value the function returns.
    func returned(_ expr: Expr) -> CheckedExpr? {
        // A function whose result type isn't known takes any value: its body gives the type, or its written type
        // failed and was reported.
        let expected = jumps.result.map { Expectation($0) }
        return expressions.check(expr, expecting: expected)
    }

    /// Checks `statement`, giving a checked statement, or nil where one fails, for each binding of a declaration
    /// and for any other statement.
    private func check(_ statement: Stmt) -> [CheckedStmt?] {
        switch statement.kind {
        case .declaration(let kind, let bindings):
            return bindings.map { bindingChecker.check($0, declaredWith: kind) }
        case .expression(let expr):
            return [checkUnused(expr).map { .expression($0) }]
        case .drop(let value):
            return [expressions.check(value).map { .expression($0) }]
        case .assign(let target, let op, let value):
            return [assignmentChecker.assign(value, op: op, to: target, in: statement.range)]
        case .ifStmt(let ifExpr):
            return [checkIf(ifExpr, in: statement.range)]
        case .whileStmt(let condition, let body):
            return [checkWhile(condition, body: body)]
        case .breakStmt:
            return [isInsideLoop("break", at: statement.range) ? .breakStmt : nil]
        case .continueStmt:
            return [isInsideLoop("continue", at: statement.range) ? .continueStmt : nil]
        case .returnStmt(let value?):
            return [returned(value).map { .returnStmt($0) }]
        case .returnStmt(nil):
            return [checkEmptyReturn(at: statement.range)]
        // A statement that failed to parse was reported there, and leaves the body tainted.
        case .error:
            errors.taints.taint()
            return []
        }
    }

    /// Checks `ifExpr`, the `if` that `range` covers, as a statement, whose branches give no value.
    private func checkIf(_ ifExpr: IfExpr, in range: SourceRange) -> CheckedStmt? {
        // Check the condition, and each branch as a block of statements.
        let condition = expressions.check(ifExpr.condition, expecting: Expectation(.bool))
        let then = CheckedBranch(statements: check(ifExpr.then), value: nil)
        let otherwise = CheckedBranch(statements: ifExpr.otherwise.map { check($0) } ?? [], value: nil)

        // A condition that failed was reported.
        guard let condition else { return nil }
        let kind = CheckedExprKind.if(condition: condition, then: then, otherwise: otherwise)
        return .expression(CheckedExpr(kind: kind, type: .void, range: range))
    }

    private func checkWhile(_ condition: Expr, body: Block) -> CheckedStmt? {
        let condition = expressions.check(condition, expecting: Expectation(.bool))
        let body = checkLoopBody(body)
        return condition.map { .whileStmt(condition: $0, body: body) }
    }

    /// Checks `body` as a loop's body, where a `break` or a `continue` may be.
    private func checkLoopBody(_ body: Block) -> [CheckedStmt] {
        BodyChecker(expressions: expressions.insideLoop).check(body)
    }

    /// Checks a `return` without a value, reporting it in a function that returns a value.
    private func checkEmptyReturn(at range: SourceRange) -> CheckedStmt? {
        // A Void function, or one whose result type isn't known, may return without a value.
        guard let result = jumps.result, result != .void else { return .returnStmt(nil) }
        errors.report(.missingReturnValue(type: expressions.typeName(of: result)), at: range)
        return nil
    }

    /// Checks `expr` as a statement, whose value no code uses, so it must be Void.
    private func checkUnused(_ expr: Expr) -> CheckedExpr? {
        // An expression that failed was reported.
        guard let value = expressions.check(expr) else { return nil }
        // A value that no code uses is a mistake, unless `_ =` drops it on purpose.
        guard value.type == .void else {
            errors.report(.unusedValue(type: expressions.typeName(of: value.type)), at: value.range)
            return nil
        }
        return value
    }

    /// Whether a loop encloses the `keyword` statement, reporting it when none does.
    private func isInsideLoop(_ keyword: String, at range: SourceRange) -> Bool {
        // Inside a loop, `break` and `continue` have a loop to leave or go on with.
        if jumps.loops > 0 { return true }
        errors.report(.outsideLoop(keyword: keyword), at: range)
        return false
    }
}
