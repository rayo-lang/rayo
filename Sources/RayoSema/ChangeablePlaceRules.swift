import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// The rules for a place that changes, whether an assignment changes it or `mutable` lends it for change, so that the
/// two decide alike which places can change, and a shared borrow never becomes a write. Such a place starts from a
/// local that owns its value, or from a parameter that borrows its caller's place for change, and goes only into
/// `var` fields and elements, never into a value property such as an array's count. A temporary never changes, since
/// it ends with its statement. Each conformer says what it reports where the place starts from a value or from a
/// `let`, since an assignment may still give a whole `let` its value.
protocol ChangeablePlaceRules: PlaceRules {
    var expressions: ExpressionChecker { get }

    /// The error to report where the place starts from `local`, a `let` or a `ref let`, or nil where it may. The flag
    /// says whether the place goes on into a field or an element of the local.
    func refusal(toChangeLet local: LocalID, holdsParts: Bool) -> ErrorCode?
}

extension ChangeablePlaceRules {
    /// Checks the place that `target` names under these rules. A value property and a `let` field never change,
    /// whatever holds them, so a place that names one or goes on from one is reported as that, ahead of anything the
    /// rules would refuse in the root it starts from. So a place that changes part of its root has its root checked
    /// last.
    func changedPlace(_ target: Expr) -> TypedPlace? {
        // A place that failed was reported.
        guard let changed = expressions.place(target, under: self) else { return nil }

        // A place that is its root whole had the root checked as the rules found it.
        guard !changed.place.steps.isEmpty else { return changed }
        if let refusal = refusal(toChangePartsOf: changed.place.root) {
            return refuse(refusal, at: changed.place.root.range)
        }
        return changed
    }

    /// Whether the place may start from `local`. A place that changes the local whole has it checked here; one that
    /// changes only part of it has it checked last, after the rest of the place.
    func admits(_ local: LocalID, at range: SourceRange, holdsParts: Bool) -> Bool {
        guard !holdsParts, let refusal = refusal(toChange: local, holdsParts: false) else { return true }
        expressions.file.errors.report(refusal, at: range)
        return false
    }

    /// Admits a `var` field alone, since a `let` field never changes, whatever holds it.
    func admits(_ field: Field, at nameRange: SourceRange) -> Bool {
        guard field.kind == .var else {
            expressions.file.errors.report(.assignToLetField(field: field.name), at: nameRange)
            return false
        }
        return true
    }

    /// Refuses a value property, such as an array's count, which its type fixes. No place holds its value, so neither
    /// it nor anything inside it changes.
    func place(holding property: CheckedExpr, at nameRange: SourceRange) -> TypedPlace? {
        refuse(.assignToCount, at: nameRange)
    }

    /// The error for a change of `temporary`, which ends with its statement, so the change would do nothing. It names
    /// the temporary as the source writes it.
    func refusal(toChange temporary: CheckedExpr) -> ErrorCode {
        .assignToTemporary(temporary: expressions.file.spelling(of: temporary.range))
    }

    /// Reports why the place can't change, and returns nil in place of the place.
    func refuse(_ error: ErrorCode, at range: SourceRange) -> TypedPlace? {
        expressions.file.errors.report(error, at: range)
        return nil
    }

    /// The error to report where the place changes part of `root`, or nil where it may.
    private func refusal(toChangePartsOf root: CheckedPlaceRoot) -> ErrorCode? {
        switch root {
        case .local(let local, _): refusal(toChange: local, holdsParts: true)
        case .temporary(let value): refusal(toChange: value)
        }
    }

    /// The error to report where the place starts from `local`, whole or part by part as the flag says, or nil where
    /// it may.
    private func refusal(toChange local: LocalID, holdsParts: Bool) -> ErrorCode? {
        let declared = expressions.names[local]
        return switch declared.kind {
        // A `var` and a parameter that owns its argument own their value, and a `mutable &T` parameter borrows its
        // caller's place for change, so each may change whole or part by part.
        case .var, .parameter(.owned), .parameter(.mutable): nil
        // A `&T` parameter only reads its caller's place, whole and part by part.
        case .parameter(.borrowed):
            .assignToParameter(name: declared.name, type: expressions.typeName(of: declared.type))
        case .let, .refLet: refusal(toChangeLet: local, holdsParts: holdsParts)
        }
    }
}
