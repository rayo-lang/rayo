import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks assignments and compound assignments: what they assign, and the value they give it.
struct AssignmentChecker {
    let expressions: ExpressionChecker

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
}

/// An assignment's target is a changeable place, though an assignment may also give a whole `let` its value.
extension AssignmentChecker: ChangeablePlaceRules {
    func error(naming nonPlace: NonPlaceName, _ name: String) -> ErrorCode {
        switch nonPlace {
        // `_` names no place; it only drops a value.
        case .underscore: .assignToUnderscore
        case .function: .assignToFunction(name: name)
        case .type: .assignToType(name: name)
        }
    }

    /// An assignment stores a value in its target, so it may give a whole `let` or `ref let` its value. The
    /// initialization check reports each such store but a `let`'s first on a path.
    var change: PlaceChange { .store }

    /// Refuses a part of a `let`, the one place of a `let` that a store may not change.
    func refusal(toChangeLet name: String) -> ErrorCode {
        .changeOfPartOfLet(name: name)
    }

    /// Refuses a part of a `ref let` as a part of a `let`.
    func refusal(toChangeReferenceLet name: String, holdsParts: Bool) -> ErrorCode {
        refusal(toChangeLet: name)
    }
}
