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

    /// What a binding's type annotation and value give the local it declares.
    private enum Declared {
        /// The local's type, which the source gives at `typeRange`, and its first value, if the binding gives one.
        case typed(RayoType, typeRange: SourceRange, value: CheckedExpr?)
        /// Neither an annotation nor a value, so nothing gives the local a type.
        case untyped
        /// An annotation or a value that failed, which was reported there.
        case failed

        /// What `annotation` gives the local of a binding without a value.
        init(_ annotation: Annotation) {
            switch annotation {
            case .absent:
                self = .untyped
            case .resolved(let type, let range):
                self = .typed(type, typeRange: range, value: nil)
            case .failed:
                self = .failed
            }
        }

        var value: CheckedExpr? {
            guard case .typed(_, _, let value) = self else { return nil }
            return value
        }
    }

    /// What a binding's type annotation says of the local's type.
    private enum Annotation {
        case absent
        /// The type the annotation names, and where the source writes it.
        case resolved(RayoType, range: SourceRange)
        /// An annotation that names no type, which was reported there.
        case failed
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
            guard bindsName(parameter.name, at: parameter.nameRange) else { continue }
            _ = declare(parameter.name, type: type, kind: .parameter, at: parameter.nameRange)
        }
    }

    mutating func check(_ block: Block) -> [CheckedStmt] {
        scopes.append([:])
        defer { scopes.removeLast() }
        return block.statements.flatMap { check($0) }.compactMap { $0 }
    }

    /// Looks `name` up among the body's locals and parameters, innermost block first, and among the module's
    /// functions. A call prefers the functions, even over a local whose declaration failed, since none can be
    /// called; any other use prefers the locals and parameters.
    func lookUp(_ name: String, for use: NameUse) -> NameMatch? {
        let inScope = scopeEntry(for: name).map { NameMatch.inScope($0) }
        let functions = functionMatch(for: name)
        switch use {
        case .call:
            return functions ?? inScope
        case .ordinary:
            return inScope ?? functions
        }
    }

    private func scopeEntry(for name: String) -> ScopeEntry? {
        scopes.reversed().lazy.compactMap { $0[name] }.first
    }

    /// The module's functions called `name`, unless it has none.
    private func functionMatch(for name: String) -> NameMatch? {
        let functions = declarations.functions(named: name)
        return functions.isEmpty ? nil : .functions(functions)
    }

    // MARK: Statements

    /// Checks `statement`, giving a checked statement, or nil where one fails, for each binding of a declaration
    /// and for any other statement.
    private mutating func check(_ statement: Stmt) -> [CheckedStmt?] {
        switch statement.kind {
        case .declaration(let kind, let bindings):
            return bindings.map { check($0, declaredWith: kind) }
        case .expression(let expr):
            return [checkUnused(expr).map { .expression($0) }]
        case .drop(let value):
            return [checkTaken(value).map { .expression($0) }]
        case .assign(let target, let op, let value):
            return [assign(value, op: op, to: target, in: statement.range)]
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
        let condition = check(condition, expecting: .bool)
        let then = check(then)
        let otherwise = otherwise.map { check($0) } ?? []
        return condition.map { .ifStmt(condition: $0, then: then, otherwise: otherwise) }
    }

    private mutating func checkWhile(_ condition: Expr, body: Block) -> CheckedStmt? {
        let condition = check(condition, expecting: .bool)
        let body = checkLoopBody(body)
        return condition.map { .whileStmt(condition: $0, body: body) }
    }

    /// Checks `body` as a loop's body, where a `break` or a `continue` may be.
    private mutating func checkLoopBody(_ body: Block) -> [CheckedStmt] {
        loopDepth += 1
        defer { loopDepth -= 1 }
        return check(body)
    }

    /// Checks a `return` without a value, which a function may have only when its result type is Void or isn't
    /// known.
    private mutating func checkEmptyReturn(at range: SourceRange) -> CheckedStmt? {
        guard let result, result != .void else { return .returnStmt(nil) }
        errors.report(.missingReturnValue(type: "\(result)"), at: range)
        return nil
    }

    /// Checks `expr` as the value the function returns.
    mutating func returned(_ expr: Expr) -> CheckedExpr? {
        guard let value = checkTaken(expr) else { return nil }
        guard let result else { return value }
        return expect(value, result) ? value : nil
    }

    /// Checks `expr` as a statement, whose value no code uses, so it must be Void.
    private mutating func checkUnused(_ expr: Expr) -> CheckedExpr? {
        guard let value = check(expr) else { return nil }
        guard value.type == .void else {
            errors.report(.unusedValue(type: "\(value.type)"), at: value.range)
            return nil
        }
        return value
    }

    /// Checks `binding`, which declares a local.
    private mutating func check(_ binding: Binding, declaredWith kind: BindingKind) -> CheckedStmt? {
        // Checked before the name, so a declaration of `_` still reports its type's and its value's errors.
        let declared = checkTypeAndValue(of: binding)
        guard bindsName(binding.name, at: binding.nameRange) else { return nil }
        let type = checkLocalType(declared, of: binding)
        let local = declare(binding.name, type: type, kind: LocalKind(kind), at: binding.nameRange)
        return local.map { .binding(CheckedPlace(local: $0, range: binding.nameRange), declared.value) }
    }

    /// Checks `binding`'s type annotation and value, and the value against the annotation when it has both.
    private mutating func checkTypeAndValue(of binding: Binding) -> Declared {
        let annotation = resolveAnnotation(of: binding)
        guard let valueExpr = binding.value else { return Declared(annotation) }
        guard let value = checkTaken(valueExpr) else { return .failed }
        return checkValue(value, against: annotation)
    }

    /// Resolves `binding`'s type annotation, reporting it when it names no type.
    private func resolveAnnotation(of binding: Binding) -> Annotation {
        guard let annotation = binding.type else { return .absent }
        guard let type = declarations.resolve(annotation, reporting: errors) else { return .failed }
        return .resolved(type, range: annotation.range)
    }

    /// Checks `value` against `annotation`, reporting a mismatch, and gives the local the value's type, which the
    /// source gives at the value.
    private mutating func checkValue(_ value: CheckedExpr, against annotation: Annotation) -> Declared {
        switch annotation {
        case .resolved(let type, _):
            return expect(value, type) ? .typed(type, typeRange: value.range, value: value) : .failed
        case .absent:
            return .typed(value.type, typeRange: value.range, value: value)
        case .failed:
            return .failed
        }
    }

    /// Checks that `declared` gives the local `binding` declares a type other than Void, reporting it when it
    /// doesn't, and returns that type.
    private func checkLocalType(_ declared: Declared, of binding: Binding) -> RayoType? {
        switch declared {
        case .typed(.void, let typeRange, _):
            errors.report(.voidLocal, at: typeRange)
            return nil
        case .typed(let type, _, _):
            return type
        case .untyped:
            errors.report(.missingLocalType(name: binding.name), at: binding.nameRange)
            return nil
        case .failed:
            return nil
        }
    }

    /// Whether `name` is a name to bind, reporting it when it is `_`.
    private func bindsName(_ name: String, at range: SourceRange) -> Bool {
        guard name == "_" else { return true }
        errors.report(.underscoreDeclared, at: range)
        return false
    }

    /// Checks `expr` as the value a declaration, an assignment, a `return` or `_ =` takes, which moves a local's
    /// value out of it.
    private mutating func checkTaken(_ expr: Expr) -> CheckedExpr? {
        guard let value = check(expr) else { return nil }
        // A `copy` of a local checks to a read of it too, so only a bare name moves.
        guard case .name(let name) = expr.kind, case .local(let local) = value.kind else { return value }
        return move(local, named: name, readBy: value)
    }

    /// Turns `value`, which reads `local`, into a move of its value, reporting it when `local` is a borrowed
    /// parameter, which can't be moved from, since its caller still owns the value.
    private mutating func move(_ local: LocalID, named name: String, readBy value: CheckedExpr) -> CheckedExpr? {
        guard locals[local.index].kind != .parameter else {
            errors.report(.moveFromParameter(name: name), at: value.range)
            return nil
        }
        return CheckedExpr(kind: .move(local), type: value.type, range: value.range)
    }

    /// Declares `name` in the innermost block as a new local of `type`, or, when `type` is nil or the name is
    /// declared already, as a failed declaration, whose uses report nothing more.
    private mutating func declare(_ name: String, type: RayoType?, kind: LocalKind, at range: SourceRange) -> LocalID? {
        guard !isLocal(name, reportingRedeclarationAt: range) else {
            declareFailed(name)
            return nil
        }
        guard let type else {
            declareFailed(name)
            return nil
        }
        let local = LocalID(index: locals.count)
        locals.append(CheckedLocal(name: name, type: type, kind: kind))
        scopes[scopes.count - 1][name] = .local(local)
        return local
    }

    /// Declares `name` in the innermost block as a failed declaration, whose uses report nothing more.
    private mutating func declareFailed(_ name: String) {
        scopes[scopes.count - 1][name] = .failed
    }

    /// Whether `name` already names a local or a parameter, reporting it when it does.
    private mutating func isLocal(_ name: String, reportingRedeclarationAt range: SourceRange) -> Bool {
        guard scopeEntry(for: name) != nil else { return false }
        errors.report(.alreadyDeclared(name: name), at: range)
        return true
    }

    /// Checks `target op valueExpr`, checking the value even when the target fails.
    private mutating func assign(_ valueExpr: Expr, op: AssignOperator, to target: Expr,
                                 in range: SourceRange) -> CheckedStmt? {
        let place = assignedPlace(target)
        let value = checkAssigned(valueExpr, by: op)
        guard let place, let value else { return nil }
        switch op.binary {
        case nil:
            return assign(value, to: place)
        case let binaryOp?:
            return compoundAssign(value, binaryOp, spelled: op.rawValue, to: place, in: range)
        }
    }

    /// Checks `expr` as the value an assignment with `op` takes: a plain assignment moves a local's value, and a
    /// compound one reads it.
    private mutating func checkAssigned(_ expr: Expr, by op: AssignOperator) -> CheckedExpr? {
        op.binary == nil ? checkTaken(expr) : check(expr)
    }

    /// Checks `place = value`, whose value must have the type of the local.
    private mutating func assign(_ value: CheckedExpr, to place: CheckedPlace) -> CheckedStmt? {
        guard expect(value, locals[place.local.index].type) else { return nil }
        return .assign(place, value)
    }

    /// Checks `place op= value`, whose operator the source spells `spelled`, as `place op value`.
    private mutating func compoundAssign(_ value: CheckedExpr, _ op: BinaryOperator, spelled: String,
                                         to place: CheckedPlace, in range: SourceRange) -> CheckedStmt? {
        let current = CheckedExpr(kind: .local(place.local), type: locals[place.local.index].type, range: place.range)
        guard binary(op, current, value, spelled: spelled, in: range) != nil else { return nil }
        return .compoundAssign(place, op, value)
    }

    /// The place that `target` names, when it names a local that may be assigned.
    private mutating func assignedPlace(_ target: Expr) -> CheckedPlace? {
        guard let local = assignedLocal(target) else { return nil }
        guard isAssignable(local, at: target.range) else { return nil }
        return CheckedPlace(local: local, range: target.range)
    }

    /// Whether `local` may be assigned, reporting it when it can't. A `let` may be, though only once on each path,
    /// which control flow decides.
    private mutating func isAssignable(_ local: LocalID, at range: SourceRange) -> Bool {
        guard locals[local.index].kind == .parameter else { return true }
        errors.report(.assignToParameter(name: locals[local.index].name), at: range)
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

private extension LocalKind {
    /// The kind of local that a declaration with `kind` declares.
    init(_ kind: BindingKind) {
        switch kind {
        case .let: self = .let
        case .var: self = .var
        }
    }
}
