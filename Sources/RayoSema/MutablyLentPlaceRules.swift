import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// The rules for the place that `mutable` lends for change, which must be changeable, as an assignment's target must.
/// A `let` is never lent so, even whole, though an assignment may give it its value.
struct MutablyLentPlaceRules {
    let expressions: ExpressionChecker
    /// Where the source writes the `mutable` and its place.
    let lentRange: SourceRange
}

extension MutablyLentPlaceRules: ChangeablePlaceRules {
    /// Refuses a place that starts from a value, which lies in a temporary that dies with its statement, as an
    /// unsupported `mutable`. The value is still checked, for its own errors.
    func root(_ expr: Expr, holdsParts: Bool) -> TypedPlace? {
        guard expressions.check(expr) != nil else { return nil }
        expressions.file.errors.report(.unsupportedMutableReference, at: lentRange)
        return nil
    }

    func error(naming nonPlace: NonPlaceName, _ name: String) -> ErrorCode {
        expressions.error(naming: nonPlace, name)
    }

    /// Refuses a `let` and a `ref let`, whole or part by part, since a `mutable` never gives a place its value.
    func refusal(toChangeLet local: LocalID, holdsParts: Bool) -> ErrorCode? {
        let declared = expressions.names[local]
        // A `let` owns its value, which a `var` would let change, whole or part by part.
        guard declared.kind == .refLet else { return .mutableOfLet(name: declared.name) }
        // A part of a `ref let` is refused as an assignment into it is.
        return holdsParts ? .assignToPartOfLet(name: declared.name) : .mutableOfReferenceLet(name: declared.name)
    }
}
