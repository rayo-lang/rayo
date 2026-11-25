import RayoCheckedProgram
import RayoSource

/// A place that the source writes on its own, such as `boss` or `e.stats`, checked on its own: the place, the type of
/// the value it holds, and where the source writes it. It waits for its position, which decides whether it copies the
/// place's value, moves it out, lends the place or borrows it.
struct BarePlace {
    var place: CheckedPlace
    /// The type of the value the place holds.
    var placeType: RayoType
    /// Where the source writes the place.
    var range: SourceRange

    /// The place as the value of a position that makes `use` of it.
    func expression(as use: PlaceUse) -> CheckedExpr {
        CheckedExpr(kind: .place(place, use), type: placeType, range: range)
    }
}

extension BarePlace: WaitingValue {
    /// The type of the place's value, whatever the position.
    var type: RayoType? { placeType }

    var defaultType: RayoType? { placeType }

    func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
        TypeFit.fits(placeType, type)
    }

    /// The place as `position` takes it, since its type is its own wherever it stands.
    func settled(toward type: RayoType?, at position: Position, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.given(self, to: position)
    }

    /// The place as the position `expected` names takes it, where it has the expected type. A place of another type is
    /// reported as a mismatch, and its position takes nothing of it.
    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        guard expressions.fits(placeType, at: range, expected) else { return nil }
        return expressions.given(self, to: expected.position)
    }

    /// Reports nothing: the place was checked as the source wrote it.
    func reportErrors(by expressions: ExpressionChecker) {}
}
