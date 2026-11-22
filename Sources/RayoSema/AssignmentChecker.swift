import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks assignments and compound assignments: what they assign, and the value they give it.
struct AssignmentChecker {
    let expressions: ExpressionChecker

    private var names: NameScopes { expressions.names }
    private var errors: ErrorList { expressions.file.errors }
    private var declarations: Declarations { expressions.file.declarations }

    /// Checks an assignment, or a compound assignment such as `+=`. The value is checked even when the target can't
    /// be assigned, so mistakes in it are still reported.
    func assign(_ valueExpr: Expr, op: AssignOperator, to target: Expr, in range: SourceRange) -> CheckedStmt? {
        let current = changedPlace(target)
        let value = checkAssigned(valueExpr, by: op, to: current?.type)
        guard let current, let value else { return nil }

        return switch op.binary {
        case nil: plainAssign(value, to: current)
        case let binaryOp?:
            compoundAssign(value, CheckedBinaryOperator(binaryOp), spelled: op.rawValue, to: current, in: range)
        }
    }

    /// Checks an assignment of `value` to `place` with `=`. Its target owns what it holds, so it can't borrow a place
    /// that `value` hands it, which is reported.
    private func plainAssign(_ value: CheckedExpr, to place: TypedPlace) -> CheckedStmt {
        expressions.reportHandedPlaces(of: value, as: ErrorCode.assignmentBorrowsPlace)
        return .assign(place.place, value)
    }

    /// Checks the place that an assignment's target names, under the rules for a place an assignment changes. A
    /// value property, such as an array's count, never changes, whatever holds it, so a target that names one or goes
    /// on from one is reported as that, ahead of anything the rules would refuse in the place that holds it. So a
    /// target that changes part of its root has its root checked last.
    private func changedPlace(_ target: Expr) -> TypedPlace? {
        // A target that failed was reported.
        guard let changed = expressions.place(target, under: self) else { return nil }

        // A target that names its root whole had the root checked as the rules found it.
        guard !changed.place.steps.isEmpty else { return changed }
        if let refusal = refusal(toChangePartsOf: changed.place.root) {
            return refuse(refusal, at: changed.place.root.range)
        }
        return changed
    }

    /// The error to report when an assignment may not change part of a place that starts from `root`, or nil when
    /// it may.
    private func refusal(toChangePartsOf root: CheckedPlaceRoot) -> ErrorCode? {
        switch root {
        case .local(let local, _): refusal(toChange: local, holdsParts: true)
        // A value that no local holds is no place an assignment can change.
        case .temporary: .assignToNonLocal
        }
    }

    /// Checks the value an assignment gives its target. It is checked against the target's type where that is known,
    /// and by itself where the target can't be assigned.
    private func checkAssigned(_ expr: Expr, by op: AssignOperator, to type: RayoType?) -> CheckedExpr? {
        // A plain assignment takes the value, which must have the place's type.
        if op.binary == nil {
            expressions.check(expr, expecting: type.map { Expectation($0) })
        } else {
            // A compound one reads it, as its operator's right operand, so an untyped value takes the place's type
            // as the other operand's.
            expressions.value(of: expr).flatMap { expressions.settled($0, toward: type) }
        }
    }

    /// Checks a compound assignment such as `x += 1` the way it checks the operation it applies, `x + 1`, so it
    /// reports the same mistakes in the operands.
    private func compoundAssign(_ value: CheckedExpr, _ op: CheckedBinaryOperator, spelled: String,
                                to place: TypedPlace, in range: SourceRange) -> CheckedStmt? {
        let current = CheckedExpr(kind: .place(place.place), type: place.type, range: place.place.range)
        // Operands the operator doesn't take were reported.
        guard expressions.binary(op, current, value, spelled: spelled, in: range) != nil else { return nil }
        return .compoundAssign(place.place, op, value)
    }

    /// The error to report when an assignment may not change a local, whole or part by part as it asks, or nil
    /// when it may.
    private func refusal(toChange local: LocalID, holdsParts: Bool) -> ErrorCode? {
        switch (names[local].kind, holdsParts) {
        // A borrowed parameter's value is its caller's, whole and part by part.
        case (.parameter(.borrowed), _): .assignToParameter(name: names[local].name)
        // An owned parameter's value is the function's, as a `var`'s is, so it may change whole or part by part.
        case (.parameter(.owned), _): nil
        // A mutable parameter's place is its caller's, which the function may change whole or part by part.
        case (.parameter(.mutable), _): nil
        // A `let` may be assigned whole, only once on each path, which the initialization check enforces; it never
        // changes part by part. A `ref let` is assigned by its declaration, so the check reports any other
        // assignment of it whole as a second one.
        case (.let, true), (.refLet, true): .assignToPartOfLet(name: names[local].name)
        case (.let, false), (.refLet, false): nil
        // A `var` owns its value, and may change it whole or part by part.
        case (.var, _): nil
        }
    }

    /// Reports why an assignment's target can't change, and returns nil in place of the target.
    private func refuse(_ error: ErrorCode, at range: SourceRange) -> TypedPlace? {
        errors.report(error, at: range)
        return nil
    }
}

/// The rules for the place an assignment changes: it starts from a local that may change, and goes only into fields
/// declared with `var`, never into a value property such as an array's count.
extension AssignmentChecker: PlaceRules {
    /// Checks a target's root that is no name, such as a call. Where the target names the root whole, it is refused
    /// at once. Where the target goes on from it, it is checked as a value that no local holds, so a value property
    /// along the target is reported first, and the root is refused last.
    func root(_ expr: Expr, holdsParts: Bool) -> TypedPlace? {
        guard holdsParts else { return refuse(.assignToNonLocal, at: expr.range) }
        // A value that failed was reported, and so is one too large for the stack, where a temporary lies.
        guard let value = expressions.check(expr),
              let held = declarations.fittingOnStack(value, reporting: errors) else { return nil }
        return (CheckedPlace(root: .temporary(held)), held.type)
    }

    /// Whether an assignment may change `local` as its target asks. A target that changes the local whole has it
    /// checked here; one that changes only part of it has it checked last, after the rest of the target.
    func admits(_ local: LocalID, at range: SourceRange, holdsParts: Bool) -> Bool {
        guard !holdsParts, let refusal = refusal(toChange: local, holdsParts: holdsParts) else { return true }
        errors.report(refusal, at: range)
        return false
    }

    func error(naming nonPlace: NonPlaceName, _ name: String) -> ErrorCode {
        switch nonPlace {
        // `_` names no place; it only drops a value.
        case .underscore: .assignToNonLocal
        case .function: .assignToFunction(name: name)
        case .type: .assignToType(name: name)
        }
    }

    func admits(_ field: Field, at nameRange: SourceRange) -> Bool {
        // A `let` field never changes, whatever holds it.
        guard field.kind == .var else {
            errors.report(.assignToLetField(field: field.name), at: nameRange)
            return false
        }
        return true
    }

    func place(holding property: CheckedExpr, at nameRange: SourceRange) -> TypedPlace? {
        // A value property gives a value that no place holds, such as an array's count, which its type fixes, so
        // neither it nor anything inside it changes.
        refuse(.assignToCount, at: nameRange)
    }
}
