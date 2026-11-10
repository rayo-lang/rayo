import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks assignments and compound assignments: what they assign, and the value they give it.
struct AssignmentChecker {
    let expressions: ExpressionChecker

    private var names: NameScopes { expressions.names }
    private var errors: ErrorList { expressions.file.errors }

    /// Checks `target op valueExpr`, checking the value even when the target fails.
    func assign(_ valueExpr: Expr, op: AssignOperator, to target: Expr, in range: SourceRange) -> CheckedStmt? {
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
    private func checkAssigned(_ expr: Expr, by op: AssignOperator) -> CheckedExpr? {
        op.binary == nil ? expressions.checkTaken(expr) : expressions.check(expr)
    }

    /// Checks `place = value`, whose value must have the type of the local.
    private func assign(_ value: CheckedExpr, to place: CheckedPlace) -> CheckedStmt? {
        // A value of another type was reported.
        guard expressions.expect(value, names[place.local].type) else { return nil }
        return .assign(place, value)
    }

    /// Checks `place op= value`, whose operator the source spells `spelled`, as `place op value`.
    private func compoundAssign(_ value: CheckedExpr, _ op: BinaryOperator, spelled: String,
                                to place: CheckedPlace, in range: SourceRange) -> CheckedStmt? {
        let current = CheckedExpr(kind: .local(place.local), type: names[place.local].type, range: place.range)
        // Operands the operator doesn't take were reported.
        guard expressions.binary(op, current, value, spelled: spelled, in: range) != nil else { return nil }
        return .compoundAssign(place, op, value)
    }

    /// The place that `target` names, when it names a local that may be assigned.
    private func assignedPlace(_ target: Expr) -> CheckedPlace? {
        guard let local = assignedLocal(target) else { return nil }
        guard isAssignable(local, at: target.range) else { return nil }
        return CheckedPlace(local: local, range: target.range)
    }

    /// Whether `local` may be assigned, reporting it when it can't.
    private func isAssignable(_ local: LocalID, at range: SourceRange) -> Bool {
        // Any local but a borrowed parameter may be; a `let` only once on each path, which the initialization check
        // enforces.
        guard names[local].kind == .parameter else { return true }
        errors.report(.assignToParameter(name: names[local].name), at: range)
        return false
    }

    /// The local that `target` names, reporting it when it names none, unless its declaration failed.
    private func assignedLocal(_ target: Expr) -> LocalID? {
        // Only a local's name can be assigned, and `_` names none.
        guard case .name(let name) = target.kind, name != "_" else {
            errors.report(.assignToNonLocal, at: target.range)
            return nil
        }
        return local(named: name, at: target.range)
    }

    /// The local called `name`, which an assignment's target names at `range`, reporting it when there is none,
    /// unless its declaration failed.
    private func local(named name: String, at range: SourceRange) -> LocalID? {
        switch names.lookUp(name, for: .ordinary) {
        // A local is the assignment's.
        case .inScope(.local(let local)):
            return local

        // A local whose declaration failed was reported there.
        case .inScope(.failed):
            return nil

        // A function can't be assigned.
        case .functions:
            errors.report(.assignToFunction(name: name), at: range)
            return nil

        // Nothing has the name.
        case nil:
            errors.report(.notDeclared(name: name), at: range)
            return nil
        }
    }
}
