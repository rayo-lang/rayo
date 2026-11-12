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
        let current = assignedPlace(target)
        let value = checkAssigned(valueExpr, by: op)
        guard let current, let value else { return nil }

        switch op.binary {
        case nil:
            return assign(value, to: current)
        case let binaryOp?:
            return compoundAssign(value, binaryOp, spelled: op.rawValue, to: current, in: range)
        }
    }

    /// Checks `expr` as the value an assignment with `op` takes: a plain assignment moves a local's value, and a
    /// compound one reads it.
    private func checkAssigned(_ expr: Expr, by op: AssignOperator) -> CheckedExpr? {
        op.binary == nil ? expressions.checkTaken(expr) : expressions.check(expr)
    }

    /// Checks `place = value`, where `current` reads the place, whose type the value must have.
    private func assign(_ value: CheckedExpr, to current: CheckedExpr) -> CheckedStmt? {
        // A value of another type was reported.
        guard expressions.expect(value, current.type) else { return nil }
        return .assign(place(readBy: current), value)
    }

    /// Checks `place op= value`, where `current` reads the place and the source spells the operator `spelled`, as
    /// `place op value`.
    private func compoundAssign(_ value: CheckedExpr, _ op: BinaryOperator, spelled: String,
                                to current: CheckedExpr, in range: SourceRange) -> CheckedStmt? {
        // Operands the operator doesn't take were reported.
        guard expressions.binary(op, current, value, spelled: spelled, in: range) != nil else { return nil }
        return .compoundAssign(place(readBy: current), op, value)
    }

    /// The place that `read`, a read of a local or of a field inside it, reads.
    private func place(readBy read: CheckedExpr) -> CheckedPlace {
        // Step out from the field to the local that holds it, collecting the fields innermost first.
        var fields: [Int] = []
        var value = read
        while case .field(let structure, let index) = value.kind {
            fields.append(index)
            value = structure
        }

        // Only a read of a local starts a path of fields that may be assigned.
        guard case .local(let local) = value.kind else { preconditionFailure("an assigned place lies in a local") }
        return CheckedPlace(local: local, fields: fields.reversed(), range: read.range)
    }

    /// Checks `target` as the place an assignment changes, a local or a field of one, and returns the read of its
    /// current value, or nil when it can't be assigned, which was reported.
    private func assignedPlace(_ target: Expr) -> CheckedExpr? {
        // A local's name assigns the whole local; `_`, and anything but a name or a member, names no place.
        switch target.kind {
        case .name(let name) where name != "_": assignableLocal(named: name, at: target.range)
        // A member assigns a field of a struct whose fields may change.
        case .member(let base, let name, let nameRange):
            assignedField(named: name, at: nameRange, of: base, in: target.range)
        default: refuse(.assignToNonLocal, at: target.range)
        }
    }

    /// Checks `base`, the struct whose field an assignment's target names, as a local, or a field of one, whose
    /// fields may change, and returns the read of its current value, or nil when they can't, which was reported.
    private func changedStructure(_ base: Expr) -> CheckedExpr? {
        // A local's name names a local whose own fields must be able to change; `_`, and anything but a name or a
        // member, names no place.
        switch base.kind {
        case .name(let name) where name != "_": localWithChangeableFields(named: name, at: base.range)
        // A member names a field that must itself be one an assignment may change.
        case .member(let structure, let name, let nameRange):
            assignedField(named: name, at: nameRange, of: structure, in: base.range)
        default: refuse(.assignToNonLocal, at: base.range)
        }
    }

    /// Checks `base.name`, where the source writes `name` at `nameRange`, as a field an assignment may change, and
    /// returns the read of its current value, or nil when it can't be changed, which was reported.
    private func assignedField(named name: String, at nameRange: SourceRange, of base: Expr,
                               in range: SourceRange) -> CheckedExpr? {
        // A struct whose fields can't change was reported.
        guard let structure = changedStructure(base) else { return nil }
        // So was a name that names no field of it.
        guard let field = expressions.field(named: name, at: nameRange, of: structure, in: range) else { return nil }
        // A `let` field never changes, whatever holds it.
        guard field.kind == .var else { return refuse(.assignToLetField(field: name), at: nameRange) }
        return field.read
    }

    /// The read of the local called `name`, which the source names at `range`, when it may be assigned whole.
    /// Reports it when it can't, or when no local has the name.
    private func assignableLocal(named name: String, at range: SourceRange) -> CheckedExpr? {
        // A name that names no local was reported.
        guard let local = local(named: name, at: range) else { return nil }
        // Any local but a borrowed parameter may be assigned; a `let` only once on each path, which the
        // initialization check enforces.
        guard names[local].kind != .parameter else {
            return refuse(.assignToParameter(name: names[local].name), at: range)
        }
        return read(of: local, at: range)
    }

    /// The read of the local called `name`, which the source names at `range`, when its fields may be assigned.
    /// Reports it when they can't, or when no local has the name.
    private func localWithChangeableFields(named name: String, at range: SourceRange) -> CheckedExpr? {
        // A name that names no local was reported.
        guard let local = local(named: name, at: range) else { return nil }

        // A `var` owns its value, and may change it field by field. A `let` never changes, even field by field, and
        // a borrowed parameter's value is its caller's.
        let refusal: ErrorCode? = switch names[local].kind {
        case .var: nil
        case .let: .assignToFieldOfLet(name: names[local].name)
        case .parameter: .assignToParameter(name: names[local].name)
        }
        // A local whose fields can't change is reported.
        if let refusal { return refuse(refusal, at: range) }
        return read(of: local, at: range)
    }

    /// The read of `local`'s current value, which the source names at `range`.
    private func read(of local: LocalID, at range: SourceRange) -> CheckedExpr {
        CheckedExpr(kind: .local(local), type: names[local].type, range: range)
    }

    /// Reports `error` at `range`, the target it refuses, and returns nil in place of the target's read.
    private func refuse(_ error: ErrorCode, at range: SourceRange) -> CheckedExpr? {
        errors.report(error, at: range)
        return nil
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

        // A struct's name is a type, which can't be assigned.
        case .structure:
            errors.report(.assignToType(name: name), at: range)
            return nil

        // Nothing has the name.
        case nil:
            errors.report(.notDeclared(name: name), at: range)
            return nil
        }
    }
}
