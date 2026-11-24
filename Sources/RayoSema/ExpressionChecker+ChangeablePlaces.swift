import RayoCheckedProgram
import RayoSource
import RayoSyntax

extension ExpressionChecker {
    /// The place that `expr` names, where the `mutable` written at `range` lends it for change. Reports a place that
    /// isn't changeable, so that a shared borrow never becomes a write.
    func changeablePlace(_ expr: Expr, lentAt range: SourceRange) -> TypedPlace? {
        // A place that failed was reported.
        guard let lent = place(expr, under: self) else { return nil }
        guard isChangeable(lent.place) else {
            file.errors.report(.unsupportedMutableReference, at: range)
            return nil
        }
        return lent
    }

    /// Whether `place` is changeable: it starts from a local that may change, and goes into `var` fields and
    /// elements alone. A place in a temporary isn't, since the temporary dies with its statement.
    private func isChangeable(_ place: CheckedPlace) -> Bool {
        guard let local = place.local, names[local].kind.isChangeable else { return false }

        // Each field the place goes into is looked up in the struct that holds it, whose declaration says whether the
        // field may change; an element changes wherever its array does.
        var type = names[local].type
        for step in place.steps {
            switch (step, type) {
            case (.field(let index, _), .named(.structure(let id))):
                let field = file.declarations.types.fields(of: id)[index]
                guard field.kind == .var else { return false }
                type = field.type
            case (.element, .array(_, let element)):
                type = element
            default:
                preconditionFailure("checking steps only into a struct's field or an array's element")
            }
        }
        return true
    }
}

private extension LocalKind {
    /// Whether the local is a changeable place: one that owns its value, or a parameter that borrows its caller's
    /// place for change.
    var isChangeable: Bool {
        switch self {
        case .var, .parameter(.owned), .parameter(.mutable): true
        // A `let` never changes once it has its value, and a `ref let` and a `&T` parameter only read their place.
        case .let, .refLet, .parameter(.borrowed): false
        }
    }
}
