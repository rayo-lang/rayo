import RayoSource
import RayoSyntax

/// Checks a function body: its statements, its locals and the names they declare, and its expressions.
struct BodyChecker {
    /// What a name in scope stands for.
    enum ScopeEntry {
        case local(LocalID)
        /// A name whose declaration failed, which was reported there, so its uses report nothing more.
        case failed
    }

    let declarations: Declarations
    var errors: Diagnostics
    private(set) var locals: [CheckedLocal] = []
    /// The names each enclosing block declares, innermost last.
    private var scopes: [[String: ScopeEntry]] = []
    private var loopDepth = 0

    init(declarations: Declarations, errors: Diagnostics) {
        self.declarations = declarations
        self.errors = errors
    }

    mutating func check(_ block: Block) -> [CheckedStmt] {
        scopes.append([:])
        defer { scopes.removeLast() }
        return block.statements.compactMap { check($0) }
    }

    func lookUp(_ name: String) -> ScopeEntry? {
        scopes.reversed().lazy.compactMap { $0[name] }.first
    }

    // MARK: Statements

    private mutating func check(_ statement: Stmt) -> CheckedStmt? {
        switch statement.kind {
        case .expression(let expr):
            return check(expr).map { .expression($0) }
        case .binding(let binding):
            return check(binding)
        case .assign(let target, let op, let value):
            return assign(value, op: op, to: target, in: statement.range)
        case .ifStmt(let condition, let then, let otherwise):
            let condition = check(condition, expecting: .bool)
            let then = check(then)
            let otherwise = otherwise.map { check($0) } ?? []
            return condition.map { .ifStmt(condition: $0, then: then, otherwise: otherwise) }
        case .whileStmt(let condition, let body):
            let condition = check(condition, expecting: .bool)
            loopDepth += 1
            let body = check(body)
            loopDepth -= 1
            return condition.map { .whileStmt(condition: $0, body: body) }
        case .breakStmt:
            return isInsideLoop("break", at: statement.range) ? .breakStmt : nil
        case .continueStmt:
            return isInsideLoop("continue", at: statement.range) ? .continueStmt : nil
        }
    }

    private mutating func check(_ binding: Binding) -> CheckedStmt? {
        let declared = binding.type.flatMap { declarations.resolve($0, reporting: &errors) }
        let value = checkTaken(binding.value)
        if binding.name == "_" {
            errors.error("'_' can't be declared", at: binding.nameRange)
            return nil
        }
        guard let value, binding.type == nil || declared != nil else {
            return declareFailed(binding.name, at: binding.nameRange)
        }
        let type = declared ?? value.type
        guard expect(value, type) else { return declareFailed(binding.name, at: binding.nameRange) }
        if type == .void {
            errors.error("a local can't have type Void", at: value.range)
            return declareFailed(binding.name, at: binding.nameRange)
        }
        guard let local = declare(binding.name, type: type, isVar: binding.kind == .var, at: binding.nameRange)
        else { return nil }
        return .binding(local, value)
    }

    /// Checks `expr` as the value a declaration or an assignment takes, which takes a local's value only
    /// with `copy`.
    private mutating func checkTaken(_ expr: Expr) -> CheckedExpr? {
        guard let value = check(expr) else { return nil }
        if case .name(let name) = expr.kind, case .local = value.kind {
            errors.error("take the value of '\(name)' with 'copy \(name)'", at: expr.range)
            return nil
        }
        return value
    }

    private mutating func declare(_ name: String, type: RayoType, isVar: Bool, at range: SourceRange) -> LocalID? {
        guard !isVisible(name, reportingRedeclarationAt: range) else {
            scopes[scopes.count - 1][name] = .failed
            return nil
        }
        let local = LocalID(index: locals.count)
        locals.append(CheckedLocal(name: name, type: type, isVar: isVar))
        scopes[scopes.count - 1][name] = .local(local)
        return local
    }

    /// Declares `name` for a declaration that failed, so that its uses report nothing more.
    private mutating func declareFailed(_ name: String, at range: SourceRange) -> CheckedStmt? {
        _ = isVisible(name, reportingRedeclarationAt: range)
        scopes[scopes.count - 1][name] = .failed
        return nil
    }

    /// Whether `name` already names a local or a function, reporting it when it does.
    private mutating func isVisible(_ name: String, reportingRedeclarationAt range: SourceRange) -> Bool {
        guard lookUp(name) != nil || declarations.functionNames.contains(name) else { return false }
        errors.error("'\(name)' is already declared", at: range)
        return true
    }

    private mutating func assign(_ valueExpr: Expr, op: AssignOperator, to target: Expr,
                                 in range: SourceRange) -> CheckedStmt? {
        let local = assignedLocal(target)
        let canChange = local.map { isVar($0, at: target.range) } ?? false
        let value = op.binary == nil ? checkTaken(valueExpr) : check(valueExpr)
        guard let local, canChange, let value else { return nil }
        let place = CheckedPlace(local: local, range: target.range)
        let type = locals[local.index].type
        guard let binaryOp = op.binary else { return expect(value, type) ? .assign(place, value) : nil }
        let current = CheckedExpr(kind: .local(local), type: type, range: target.range)
        guard binary(binaryOp, current, value, spelled: op.rawValue, in: range) != nil else { return nil }
        return .compoundAssign(place, binaryOp, value)
    }

    /// Whether `local` is a `var`, reporting it when it isn't.
    private mutating func isVar(_ local: LocalID, at range: SourceRange) -> Bool {
        if locals[local.index].isVar { return true }
        errors.error("'\(locals[local.index].name)' is a 'let', so it can't change", at: range)
        return false
    }

    /// The local that `target` names, when it names one.
    private mutating func assignedLocal(_ target: Expr) -> LocalID? {
        switch target.kind {
        case .name(let name) where name != "_":
            switch lookUp(name) {
            case .local(let local):
                return local
            case .failed:
                break
            case nil where declarations.functionNames.contains(name):
                errors.error("'\(name)' is a function, so it can't change", at: target.range)
            case nil:
                errors.error("'\(name)' isn't declared", at: target.range)
            }
        default:
            errors.error("only a place can be assigned", at: target.range)
        }
        return nil
    }

    /// Whether a loop encloses the `keyword` statement, reporting it when none does.
    private mutating func isInsideLoop(_ keyword: String, at range: SourceRange) -> Bool {
        if loopDepth > 0 { return true }
        errors.error("'\(keyword)' is only allowed inside a loop", at: range)
        return false
    }
}
