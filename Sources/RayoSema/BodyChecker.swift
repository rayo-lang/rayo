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
            return check(binding, in: statement.range)
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
        case .breakStmt, .continueStmt:
            return loopExit(statement)
        case .forRange:
            errors.unsupported("'for'", at: statement.range)
        case .returnStmt:
            errors.unsupported("'return'", at: statement.range)
        case .doBlock:
            errors.unsupported("'do'", at: statement.range)
        }
        return nil
    }

    private mutating func check(_ binding: Binding, in range: SourceRange) -> CheckedStmt? {
        let declared = binding.type.flatMap { declarations.resolve($0, reporting: &errors) }
        guard let valueExpr = binding.value else {
            errors.unsupported("a declaration without a value", at: range)
            return declareFailed(binding.name, at: binding.nameRange)
        }
        let value = check(valueExpr)
        guard let value, binding.type == nil || declared != nil else {
            return declareFailed(binding.name, at: binding.nameRange)
        }
        let type = declared ?? value.type
        guard expect(value, type) else { return declareFailed(binding.name, at: binding.nameRange) }
        if type == .void {
            errors.unsupported("a value of type Void", at: value.range)
            return declareFailed(binding.name, at: binding.nameRange)
        }
        guard let local = declare(binding.name, type: type, isVar: binding.kind == .var, at: binding.nameRange)
        else { return nil }
        return .binding(local, value)
    }

    private mutating func declare(_ name: String, type: RayoType, isVar: Bool, at range: SourceRange) -> LocalID? {
        guard lookUp(name) == nil else {
            errors.unsupported("declaring '\(name)' while another '\(name)' is visible", at: range)
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
        if lookUp(name) != nil {
            errors.unsupported("declaring '\(name)' while another '\(name)' is visible", at: range)
        }
        scopes[scopes.count - 1][name] = .failed
        return nil
    }

    private mutating func assign(_ valueExpr: Expr, op: AssignOperator, to target: Expr,
                                 in range: SourceRange) -> CheckedStmt? {
        let local = assignedLocal(target)
        let value = check(valueExpr)
        guard let local, let value else { return nil }
        let place = CheckedPlace(local: local, range: target.range)
        let current = CheckedExpr(kind: .local(local), type: locals[local.index].type, range: target.range)
        guard locals[local.index].isVar else {
            errors.error("'\(locals[local.index].name)' is a 'let', so it can't change", at: target.range)
            return nil
        }
        if let binaryOp = op.binary {
            guard binary(binaryOp, current, value, spelled: op.rawValue, in: range) != nil else { return nil }
            return .compoundAssign(place, binaryOp, value)
        }
        return expect(value, current.type) ? .assign(place, value) : nil
    }

    /// The local that `target` names, when it names one that can be assigned.
    private mutating func assignedLocal(_ target: Expr) -> LocalID? {
        guard case .name(let name, let typeArguments) = target.kind, typeArguments.isEmpty else {
            errors.error("only a place can be assigned", at: target.range)
            return nil
        }
        switch lookUp(name) {
        case .local(let local):
            return local
        case .failed:
            return nil
        case nil:
            errors.error("'\(name)' isn't declared", at: target.range)
            return nil
        }
    }

    private mutating func loopExit(_ statement: Stmt) -> CheckedStmt? {
        let isBreak: Bool
        if case .breakStmt = statement.kind { isBreak = true } else { isBreak = false }
        guard loopDepth > 0 else {
            errors.error("'\(isBreak ? "break" : "continue")' is only allowed inside a loop", at: statement.range)
            return nil
        }
        return isBreak ? .breakStmt : .continueStmt
    }
}
