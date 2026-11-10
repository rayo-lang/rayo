import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a function body's statements, block by block, and the loops and returns among them.
struct BodyChecker {
    private let expressions: ExpressionChecker
    /// The function's result type, or nil when it isn't known.
    let result: RayoType?
    private var loopDepth = 0

    /// A checker of the body of a function whose result type is `result`, with `parameters`, whose types are
    /// `types`, as its first locals, reporting what in them can't be declared.
    init(file: FileChecker, parameters: [Param], types: [RayoType?], result: RayoType?) {
        // Give the body names of its own, which every checker it builds shares.
        expressions = ExpressionChecker(file: file, names: NameScopes(file: file))
        self.result = result

        // Declare the parameters in the scope around the body's blocks.
        bindingChecker.declare(parameters, types: types)
    }

    /// The body's locals, indexed by `LocalID`, its parameters first.
    var locals: [CheckedLocal] { expressions.names.locals }

    private var errors: ErrorList { expressions.file.errors }
    private var bindingChecker: BindingChecker { BindingChecker(expressions: expressions) }
    private var assignmentChecker: AssignmentChecker { AssignmentChecker(expressions: expressions) }

    mutating func check(_ block: Block) -> [CheckedStmt] {
        expressions.names.enterBlock()
        defer { expressions.names.leaveBlock() }
        return block.statements.flatMap { check($0) }.compactMap { $0 }
    }

    /// Checks `expr` as the value the function returns.
    func returned(_ expr: Expr) -> CheckedExpr? {
        // A value that failed was reported.
        guard let value = expressions.checkTaken(expr) else { return nil }
        // A function whose result type isn't known takes any value: its body gives the type, or its written type
        // failed and was reported.
        guard let result else { return value }
        return expressions.expect(value, result) ? value : nil
    }

    /// Checks `statement`, giving a checked statement, or nil where one fails, for each binding of a declaration
    /// and for any other statement.
    private mutating func check(_ statement: Stmt) -> [CheckedStmt?] {
        switch statement.kind {
        case .declaration(let kind, let bindings):
            return bindings.map { bindingChecker.check($0, declaredWith: kind) }
        case .expression(let expr):
            return [checkUnused(expr).map { .expression($0) }]
        case .drop(let value):
            return [expressions.checkTaken(value).map { .expression($0) }]
        case .assign(let target, let op, let value):
            return [assignmentChecker.assign(value, op: op, to: target, in: statement.range)]
        case .ifStmt(let condition, let then, let otherwise):
            return [checkIf(condition, then: then, otherwise: otherwise)]
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
        }
    }

    private mutating func checkIf(_ condition: Expr, then: Block, otherwise: Block?) -> CheckedStmt? {
        let condition = expressions.check(condition, expecting: .bool)
        let then = check(then)
        let otherwise = otherwise.map { check($0) } ?? []
        return condition.map { .ifStmt(condition: $0, then: then, otherwise: otherwise) }
    }

    private mutating func checkWhile(_ condition: Expr, body: Block) -> CheckedStmt? {
        let condition = expressions.check(condition, expecting: .bool)
        let body = checkLoopBody(body)
        return condition.map { .whileStmt(condition: $0, body: body) }
    }

    /// Checks `body` as a loop's body, where a `break` or a `continue` may be.
    private mutating func checkLoopBody(_ body: Block) -> [CheckedStmt] {
        loopDepth += 1
        defer { loopDepth -= 1 }
        return check(body)
    }

    /// Checks a `return` without a value, reporting it in a function that returns a value.
    private func checkEmptyReturn(at range: SourceRange) -> CheckedStmt? {
        // A Void function, or one whose result type isn't known, may return without a value.
        guard let result, result != .void else { return .returnStmt(nil) }
        errors.report(.missingReturnValue(type: "\(result)"), at: range)
        return nil
    }

    /// Checks `expr` as a statement, whose value no code uses, so it must be Void.
    private func checkUnused(_ expr: Expr) -> CheckedExpr? {
        // An expression that failed was reported.
        guard let value = expressions.check(expr) else { return nil }
        // A value that no code uses is a mistake, unless `_ =` drops it on purpose.
        guard value.type == .void else {
            errors.report(.unusedValue(type: "\(value.type)"), at: value.range)
            return nil
        }
        return value
    }

    /// Whether a loop encloses the `keyword` statement, reporting it when none does.
    private func isInsideLoop(_ keyword: String, at range: SourceRange) -> Bool {
        // Inside a loop, `break` and `continue` have a loop to leave or go on with.
        if loopDepth > 0 { return true }
        errors.report(.outsideLoop(keyword: keyword), at: range)
        return false
    }
}
