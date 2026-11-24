import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// The rules for the place that `mutable` lends for change, which must be changeable, so that a shared borrow never
/// becomes a write: it starts from a local that may change, and goes only into `var` fields and elements. Each place
/// they refuse reports the `mutable`, where the source writes it with its place, as unsupported.
struct ChangeablePlaceRules {
    let expressions: ExpressionChecker
    /// Where the source writes the `mutable` and its place.
    let lentRange: SourceRange

    /// Reports the `mutable` of a place these rules refuse.
    private func reportRefusal() {
        expressions.file.errors.report(.unsupportedMutableReference, at: lentRange)
    }
}

extension ChangeablePlaceRules: PlaceRules {
    /// Refuses a place that starts from a value, which lies in a temporary that dies with its statement. The value is
    /// still checked, for its own errors.
    func root(_ expr: Expr, holdsParts: Bool) -> TypedPlace? {
        guard expressions.check(expr) != nil else { return nil }
        reportRefusal()
        return nil
    }

    func admits(_ local: LocalID, at range: SourceRange, holdsParts: Bool) -> Bool {
        guard expressions.names[local].kind.isChangeable else {
            reportRefusal()
            return false
        }
        return true
    }

    func error(naming nonPlace: NonPlaceName, _ name: String) -> ErrorCode {
        expressions.error(naming: nonPlace, name)
    }

    /// Admits a `var` field alone, since a `let` field never changes, whatever holds it.
    func admits(_ field: Field, at nameRange: SourceRange) -> Bool {
        guard field.kind == .var else {
            reportRefusal()
            return false
        }
        return true
    }

    /// Refuses a value property, such as an array's count, whose value no place holds.
    func place(holding property: CheckedExpr, at nameRange: SourceRange) -> TypedPlace? {
        reportRefusal()
        return nil
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
