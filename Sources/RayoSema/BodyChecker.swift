import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a function body: its statements, its locals and the names they declare, and its expressions.
struct BodyChecker {
    /// What a name that a block or the parameter list declares stands for.
    enum ScopeEntry {
        case local(LocalID)
        /// A name whose declaration failed, which was reported there, so its uses report nothing more.
        case failed
    }

    /// What an unqualified name stands for where the body uses it.
    enum NameMatch {
        /// A local or a parameter.
        case inScope(ScopeEntry)
        /// The module's functions of that name, the prelude's among them.
        case functions([Signature])
    }

    /// How the body uses a name, which decides the matches its lookup skips.
    enum NameUse {
        case call
        /// Any use but a call.
        case ordinary
    }

    /// The file the body is in, which gives the result types of the functions it calls.
    let file: FileChecker
    /// The function's result type, or nil when it isn't known.
    let result: RayoType?
    private(set) var locals: [CheckedLocal] = []
    /// The names each enclosing block declares, innermost last, inside the scope of the function's parameters.
    private var scopes: [[String: ScopeEntry]] = [[:]]
    private var loopDepth = 0

    init(file: FileChecker, result: RayoType?) {
        self.file = file
        self.result = result
    }

    var declarations: Declarations { file.declarations }
    var errors: ErrorList { file.errors }

    /// Declares `parameters`, whose types are `types`, as the function's first locals, in order.
    mutating func declare(_ parameters: [Param], types: [RayoType?]) {
        for (parameter, type) in zip(parameters, types) {
            if parameter.name == "_" {
                errors.report(.underscoreDeclared, at: parameter.nameRange)
            } else if let type {
                _ = declare(parameter.name, type: type, kind: .parameter, at: parameter.nameRange)
            } else {
                _ = declareFailed(parameter.name, at: parameter.nameRange)
            }
        }
    }

    mutating func check(_ block: Block) -> [CheckedStmt] {
        scopes.append([:])
        defer { scopes.removeLast() }
        return block.statements.compactMap { check($0) }
    }

    /// Looks `name` up in the body's locals and parameters, innermost block first, then among the module's
    /// functions, and gives the nearest match. A call skips the locals and parameters, since none has a type that can
    /// be called, not even one whose declaration failed, and gives the local only when no function has the name.
    func lookUp(_ name: String, for use: NameUse) -> NameMatch? {
        let functions = declarations.functions(named: name)
        if let entry = scopeEntry(for: name), use == .ordinary || functions.isEmpty { return .inScope(entry) }
        return functions.isEmpty ? nil : .functions(functions)
    }

    private func scopeEntry(for name: String) -> ScopeEntry? {
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
        case .returnStmt(let value?):
            return returned(value).map { .returnStmt($0) }
        case .returnStmt(nil):
            guard let result, result != .void else { return .returnStmt(nil) }
            errors.report(.missingReturnValue(type: "\(result)"), at: statement.range)
            return nil
        }
    }

    /// Checks `expr` as the value the function returns.
    mutating func returned(_ expr: Expr) -> CheckedExpr? {
        guard let value = checkTaken(expr) else { return nil }
        guard let result else { return value }
        return expect(value, result) ? value : nil
    }

    private mutating func check(_ binding: Binding) -> CheckedStmt? {
        let declared = binding.type.flatMap { declarations.resolve($0, reporting: errors) }
        let value = checkTaken(binding.value)
        if binding.name == "_" {
            errors.report(.underscoreDeclared, at: binding.nameRange)
            return nil
        }
        guard let value, binding.type == nil || declared != nil else {
            return declareFailed(binding.name, at: binding.nameRange)
        }
        let type = declared ?? value.type
        guard expect(value, type) else { return declareFailed(binding.name, at: binding.nameRange) }
        if type == .void {
            errors.report(.voidLocal, at: value.range)
            return declareFailed(binding.name, at: binding.nameRange)
        }
        let kind: LocalKind = binding.kind == .var ? .var : .let
        guard let local = declare(binding.name, type: type, kind: kind, at: binding.nameRange) else { return nil }
        return .binding(local, value)
    }

    /// Checks `expr` as the value a declaration, an assignment or a `return` takes, which takes a local's value
    /// only with `copy`.
    private mutating func checkTaken(_ expr: Expr) -> CheckedExpr? {
        guard let value = check(expr) else { return nil }
        if case .name(let name) = expr.kind, case .local = value.kind {
            errors.report(.takenWithoutCopy(name: name), at: expr.range)
            return nil
        }
        return value
    }

    private mutating func declare(_ name: String, type: RayoType, kind: LocalKind, at range: SourceRange) -> LocalID? {
        guard !isLocal(name, reportingRedeclarationAt: range) else {
            scopes[scopes.count - 1][name] = .failed
            return nil
        }
        let local = LocalID(index: locals.count)
        locals.append(CheckedLocal(name: name, type: type, kind: kind))
        scopes[scopes.count - 1][name] = .local(local)
        return local
    }

    /// Declares `name` for a declaration that failed, so that its uses report nothing more.
    private mutating func declareFailed(_ name: String, at range: SourceRange) -> CheckedStmt? {
        _ = isLocal(name, reportingRedeclarationAt: range)
        scopes[scopes.count - 1][name] = .failed
        return nil
    }

    /// Whether `name` already names a local or a parameter, reporting it when it does.
    private mutating func isLocal(_ name: String, reportingRedeclarationAt range: SourceRange) -> Bool {
        guard scopeEntry(for: name) != nil else { return false }
        errors.report(.alreadyDeclared(name: name), at: range)
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
        let name = locals[local.index].name
        switch locals[local.index].kind {
        case .var:
            return true
        case .let:
            errors.report(.assignToLet(name: name), at: range)
        case .parameter:
            errors.report(.assignToParameter(name: name), at: range)
        }
        return false
    }

    /// The local that `target` names, when it names one.
    private mutating func assignedLocal(_ target: Expr) -> LocalID? {
        switch target.kind {
        case .name(let name) where name != "_":
            switch lookUp(name, for: .ordinary) {
            case .inScope(.local(let local)):
                return local
            case .inScope(.failed):
                break
            case .functions:
                errors.report(.assignToFunction(name: name), at: target.range)
            case nil:
                errors.report(.notDeclared(name: name), at: target.range)
            }
        default:
            errors.report(.assignToNonLocal, at: target.range)
        }
        return nil
    }

    /// Whether a loop encloses the `keyword` statement, reporting it when none does.
    private mutating func isInsideLoop(_ keyword: String, at range: SourceRange) -> Bool {
        if loopDepth > 0 { return true }
        errors.report(.outsideLoop(keyword: keyword), at: range)
        return false
    }
}
