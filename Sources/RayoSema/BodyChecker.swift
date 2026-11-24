import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a function body's statements, block by block, and the loops and returns among them.
struct BodyChecker {
    private let expressions: ExpressionChecker

    /// A checker of the body of a function whose result type is `result`, with `parameters`, which `signature`
    /// declares, as its first locals, reporting what in them can't be declared.
    init(file: FileChecker, parameters: [Param], declaredAs signature: [Parameter], result: RayoType?) {
        // Give the body names of its own, which every checker it builds shares.
        self.init(expressions: ExpressionChecker(file: file, names: NameScopes(file: file),
                                                 jumps: JumpTargets(result: result)))

        // Declare the parameters in the scope around the body's blocks.
        bindingChecker.declare(parameters, declaredAs: signature)
    }

    /// A checker of statements whose expressions `expressions` checks.
    init(expressions: ExpressionChecker) {
        self.expressions = expressions
    }

    /// The body's locals, indexed by `LocalID`, its parameters first.
    var locals: [CheckedLocal] { expressions.names.locals }

    private var errors: ErrorList { expressions.file.errors }
    private var declarations: Declarations { expressions.file.declarations }
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
        kept(statements.flatMap { check($0) })
    }

    /// The statements of a body whose single expression checks to `returned`: a return of its value, or none where
    /// it failed.
    func statements(returning returned: CheckedExpr?) -> [CheckedStmt] {
        kept([returned.map { .returnStmt($0) }])
    }

    /// `checked`, without the statements that failed, which only a tainted body leaves out.
    private func kept(_ checked: [CheckedStmt?]) -> [CheckedStmt] {
        // A body missing a statement has lost its meaning, so it must be tainted, which keeps it out of the checked
        // program. If a check failed without tainting the body, lowering would get a body with a statement missing
        // and compile it as if it were whole.
        let kept = checked.compactMap { $0 }
        precondition(kept.count == checked.count || errors.taints.isCheckingTaintedBody,
                     "a statement whose check fails is left out only of a tainted body")
        return kept
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
            return [checkDropped(value).map { .expression($0) }]
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
        // A statement that failed to parse was reported there, and leaves the body tainted. The names it binds are
        // declared as failed, so their uses report nothing more.
        case .error(let boundNames):
            errors.taints.taint()
            for name in boundNames { expressions.names.declareFailed(name) }
            return [nil]
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
        let alwaysHolds = Reachability.alwaysHolds(condition)
        let condition = expressions.check(condition, expecting: Expectation(.bool))
        let body = checkLoopBody(body)
        return condition.map { .whileStmt(condition: $0, alwaysHolds: alwaysHolds, body: body) }
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
        guard !TypeFit.fits(value.type, .void) else { return value }

        // A value that no code uses is a mistake, unless `_ =` drops it on purpose. The statement keeps a meaning all
        // the same: a place it names is only read, so the mistake moves nothing out of it, and any other value is
        // dropped as `_ =` drops it.
        let unused = ErrorCode.unusedValue(type: expressions.typeName(of: value.type),
                                           drop: expressions.dropSpelling(of: value))
        errors.reportKeepingMeaning(unused, at: value.range)
        guard case .place(let place) = value.kind else { return value }
        return CheckedExpr(kind: .copy(place), type: value.type, range: value.range)
    }

    /// Checks `expr` as the value of `_ =`, which a temporary holds until the statement drops it. The temporary owns
    /// its value, as any assignment's target does, so a place that the value hands it is reported as an assignment
    /// reports one: unless its type is implicitly copyable, it needs `consume` or `copy` before it.
    private func checkDropped(_ expr: Expr) -> CheckedExpr? {
        // An expression that failed was reported.
        guard let value = expressions.check(expr) else { return nil }
        expressions.reportHandedPlaces(of: value, as: ErrorCode.assignmentBorrowsPlace)
        // A temporary lies on the stack, so one too large for it is reported.
        return declarations.fittingOnStack(value, reporting: errors)
    }

    /// Whether a loop encloses the `keyword` statement, reporting it when none does.
    private func isInsideLoop(_ keyword: String, at range: SourceRange) -> Bool {
        // Inside a loop, `break` and `continue` have a loop to leave or go on with.
        if jumps.loops > 0 { return true }
        errors.report(.outsideLoop(keyword: keyword), at: range)
        return false
    }
}
