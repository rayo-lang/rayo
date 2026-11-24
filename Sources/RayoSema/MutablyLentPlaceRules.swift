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

    /// A `mutable` lends its place for change, and never gives a place its value.
    var change: PlaceChange { .modify }

    /// Refuses a `let` alike whole and part by part.
    func refusal(toChangeLet name: String) -> ErrorCode {
        .mutableOfLet(name: name)
    }

    /// Refuses a part of a `ref let` as an assignment into it is refused.
    func refusal(toChangeReferenceLet name: String, holdsParts: Bool) -> ErrorCode {
        holdsParts ? .changeOfPartOfLet(name: name) : .mutableOfReferenceLet(name: name)
    }
}
