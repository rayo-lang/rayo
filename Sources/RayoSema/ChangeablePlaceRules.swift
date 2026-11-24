import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// The rules for a place that changes, whether an assignment changes it or `mutable` lends it for change, so the two
/// decide alike which places can change. A temporary never changes, since it ends with its statement. Each conformer
/// says what it reports for a place that starts from a `let` or a `ref let`.
protocol ChangeablePlaceRules: PlaceRules {
    var expressions: ExpressionChecker { get }

    /// The error for a place that starts from the `let` called `name`, whole or part by part, or nil where it may.
    func refusal(toChangeLet name: String, holdsParts: Bool) -> ErrorCode?

    /// The error for a place that starts from the `ref let` called `name`, whole or part by part, or nil where it may.
    func refusal(toChangeReferenceLet name: String, holdsParts: Bool) -> ErrorCode?
}

extension ChangeablePlaceRules {
    /// Checks a root that is no name, such as a call or a literal, as a temporary, which never changes. A place that
    /// goes on from it has the root refused last, after the rest of the place.
    func root(_ expr: Expr, holdsParts: Bool) -> TypedPlace? {
        // A value that failed was reported, and so is one too large for the stack, where a temporary lies.
        guard let value = expressions.check(expr),
              let held = expressions.file.declarations.fittingOnStack(value, reporting: expressions.file.errors)
        else { return nil }
        guard holdsParts else { return refuse(refusal(toChange: held), at: expr.range) }
        return (CheckedPlace(root: .temporary(held)), held.type)
    }

    /// Checks the place that `target` names under these rules, checking its root last.
    func changedPlace(_ target: Expr) -> TypedPlace? {
        // A place that failed was reported.
        guard let changed = expressions.place(target, under: self) else { return nil }

        // A place that is its root whole had the root checked as the rules found it. A `let` field or a value
        // property inside the root never changes, whatever holds it, so it was reported ahead of the root.
        guard !changed.place.steps.isEmpty else { return changed }
        if let refusal = refusal(toChangePartsOf: changed.place.root) {
            return refuse(refusal, at: changed.place.root.range)
        }
        return changed
    }

    /// Whether the place may start from `local`. One that changes only part of it has it checked last.
    func admits(_ local: LocalID, at range: SourceRange, holdsParts: Bool) -> Bool {
        guard !holdsParts, let refusal = refusal(toChange: local, holdsParts: false) else { return true }
        expressions.file.errors.report(refusal, at: range)
        return false
    }

    /// Admits a `var` field alone, since a `let` field never changes, whatever holds it.
    func admits(_ field: Field, at nameRange: SourceRange) -> Bool {
        guard field.kind == .var else {
            expressions.file.errors.report(.changeOfLetField(field: field.name), at: nameRange)
            return false
        }
        return true
    }

    /// Refuses a value property, such as an array's count, whose value no place holds, so nothing in it changes.
    func place(holding property: CheckedExpr, at nameRange: SourceRange) -> TypedPlace? {
        refuse(.changeOfCount, at: nameRange)
    }

    /// The error for a change of `temporary`, which ends with its statement, so the change would do nothing.
    func refusal(toChange temporary: CheckedExpr) -> ErrorCode {
        .assignToTemporary(temporary: expressions.file.spelling(of: temporary.range))
    }

    /// Reports why the place can't change, and returns nil in place of the place.
    func refuse(_ error: ErrorCode, at range: SourceRange) -> TypedPlace? {
        expressions.file.errors.report(error, at: range)
        return nil
    }

    /// The error for a place that changes part of `root`, or nil where it may.
    private func refusal(toChangePartsOf root: CheckedPlaceRoot) -> ErrorCode? {
        switch root {
        case .local(let local, _): refusal(toChange: local, holdsParts: true)
        case .temporary(let value): refusal(toChange: value)
        }
    }

    /// The error for a place that starts from `local`, whole or part by part, or nil where it may.
    private func refusal(toChange local: LocalID, holdsParts: Bool) -> ErrorCode? {
        let declared = expressions.names[local]
        return switch declared.kind {
        // Each owns its value, or borrows its caller's place for change, so it may change whole or part by part.
        case .var, .parameter(.owned), .parameter(.mutable): nil
        // A `&T` parameter only reads its caller's place.
        case .parameter(.borrowed):
            .changeOfBorrowedParameter(name: declared.name, type: expressions.typeName(of: declared.type))
        case .let: refusal(toChangeLet: declared.name, holdsParts: holdsParts)
        case .refLet: refusal(toChangeReferenceLet: declared.name, holdsParts: holdsParts)
        }
    }
}
