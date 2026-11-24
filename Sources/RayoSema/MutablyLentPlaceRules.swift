import RayoCheckedProgram
import RayoDiagnostics
import RayoSyntax

/// The rules for the place that `mutable` lends for change, which must be changeable, as an assignment's target must.
/// A `let` is never lent so, even whole, though an assignment may give it its value.
struct MutablyLentPlaceRules {
    let expressions: ExpressionChecker
}

extension MutablyLentPlaceRules: ChangeablePlaceRules {
    func error(naming nonPlace: NonPlaceName, _ name: String) -> ErrorCode {
        expressions.error(naming: nonPlace, name)
    }

    /// Refuses a `let`, whole or part by part, since a `mutable` never gives a place its value.
    func refusal(toChangeLet name: String, holdsParts: Bool) -> ErrorCode? {
        .mutableOfLet(name: name)
    }

    /// Refuses a `ref let`, whole or part by part. A part is refused as an assignment into it is.
    func refusal(toChangeReferenceLet name: String, holdsParts: Bool) -> ErrorCode? {
        holdsParts ? .changeOfPartOfLet(name: name) : .mutableOfReferenceLet(name: name)
    }
}
