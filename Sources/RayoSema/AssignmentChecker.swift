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
        let current = expressions.place(target, under: self)
        let value = checkAssigned(valueExpr, by: op, to: current?.type)
        guard let current, let value else { return nil }

        switch op.binary {
        case nil:
            return .assign(current.place, value)
        case let binaryOp?:
            return compoundAssign(value, binaryOp, spelled: op.rawValue, to: current, in: range)
        }
    }

    /// Checks `expr` as the value an assignment with `op` gives a place of `type`, which is nil where the place can't
    /// be assigned.
    private func checkAssigned(_ expr: Expr, by op: AssignOperator, to type: RayoType?) -> CheckedExpr? {
        // A plain assignment takes the value, which must have the place's type.
        if op.binary == nil {
            expressions.check(expr, as: .take, expecting: type.map { Expectation($0) })
        } else {
            // A compound one reads it, as its operator's right operand, so an untyped value takes the place's type
            // as the other operand's.
            expressions.value(of: expr).flatMap { expressions.settled($0, toward: type) }
        }
    }

    /// Checks `place op= value`, where the source spells the operator `spelled`, as `place op value`.
    private func compoundAssign(_ value: CheckedExpr, _ op: BinaryOperator, spelled: String,
                                to place: TypedPlace, in range: SourceRange) -> CheckedStmt? {
        let current = CheckedExpr(kind: .place(place.place), type: place.type, range: place.place.range)
        // Operands the operator doesn't take were reported.
        guard expressions.binary(op, current, value, spelled: spelled, in: range) != nil else { return nil }
        return .compoundAssign(place.place, op, value)
    }

    /// The local called `name`, which the source names at `range`, as a place an assignment changes, whole or, where
    /// `holdsFields` is true, field by field. Reports it when it can't be changed so, or when no local has the name.
    private func changedLocal(named name: String, at range: SourceRange, holdsFields: Bool) -> TypedPlace? {
        // A name that names no local was reported.
        guard let local = local(named: name, at: range) else { return nil }

        // A local whose value can't change as the assignment changes it is reported.
        if let refusal = refusal(toChange: local, holdsFields: holdsFields) { return refuse(refusal, at: range) }
        return (CheckedPlace(root: .local(local, range: range)), names[local].type)
    }

    /// The error that refuses an assignment to `local`, whole or, where `holdsFields` is true, field by field, or nil
    /// where the assignment may change it.
    private func refusal(toChange local: LocalID, holdsFields: Bool) -> ErrorCode? {
        switch (names[local].kind, holdsFields) {
        // A borrowed parameter's value is its caller's, whole and field by field.
        case (.parameter, _): .assignToParameter(name: names[local].name)
        // A `let` may be assigned whole, only once on each path, which the initialization check enforces; it never
        // changes field by field.
        case (.let, true): .assignToFieldOfLet(name: names[local].name)
        // A `var` owns its value, and may change it whole or field by field.
        case (.let, false), (.var, _): nil
        }
    }

    /// Reports `error` at `range`, the target it refuses, and returns nil in place of the target.
    private func refuse(_ error: ErrorCode, at range: SourceRange) -> TypedPlace? {
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

/// The rules of a place that an assignment changes, which starts from a local that may change, and steps only into
/// `var` fields.
extension AssignmentChecker: PlaceRules {
    func root(_ expr: Expr, holdsFields: Bool) -> TypedPlace? {
        // A local's name roots the place in the local; `_`, and anything but a name or a member, names no place.
        guard case .name(let name) = expr.kind, name != "_" else { return refuse(.assignToNonLocal, at: expr.range) }
        return changedLocal(named: name, at: expr.range, holdsFields: holdsFields)
    }

    func admits(_ field: DeclaredField, at nameRange: SourceRange) -> Bool {
        // A `let` field never changes, whatever holds it.
        guard field.kind == .var else {
            errors.report(.assignToLetField(field: field.name), at: nameRange)
            return false
        }
        return true
    }
}
