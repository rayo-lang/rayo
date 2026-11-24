import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks assignments and compound assignments: what they assign, and the value they give it.
struct AssignmentChecker {
    let expressions: ExpressionChecker

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
    /// Checks a target's root that is no name, such as a call, as a temporary, which an assignment can't change. A
    /// target that goes on from it has the root refused last, after the rest of the target.
    func root(_ expr: Expr, holdsParts: Bool) -> TypedPlace? {
        // A value that failed was reported, and so is one too large for the stack, where a temporary lies.
        guard let value = expressions.check(expr),
              let held = declarations.fittingOnStack(value, reporting: errors) else { return nil }
        guard holdsParts else { return refuse(refusal(toChange: held), at: expr.range) }
        return (CheckedPlace(root: .temporary(held)), held.type)
    }

    func error(naming nonPlace: NonPlaceName, _ name: String) -> ErrorCode {
        switch nonPlace {
        // `_` names no place; it only drops a value.
        case .underscore: .assignToUnderscore
        case .function: .assignToFunction(name: name)
        case .type: .assignToType(name: name)
        }
    }

    /// Admits a whole `let`, which the initialization check lets an assignment give its value once on each path.
    func refusal(toChangeLet name: String, holdsParts: Bool) -> ErrorCode? {
        holdsParts ? .changeOfPartOfLet(name: name) : nil
    }

    /// Admits a whole `ref let` as a `let`, since its declaration gives it its value, so the initialization check
    /// reports any assignment of it whole as a second one.
    func refusal(toChangeReferenceLet name: String, holdsParts: Bool) -> ErrorCode? {
        refusal(toChangeLet: name, holdsParts: holdsParts)
    }
}
