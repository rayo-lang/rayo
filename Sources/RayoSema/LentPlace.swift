import RayoCheckedProgram
import RayoSource

/// `&place`, checked on its own: the place it lends, the type of the value the place holds, and where the source
/// writes it. Only the argument of a parameter that borrows, and a `ref let`'s value, take it, so it waits for its
/// position to say whether that is what the position is.
struct LentPlace {
    var place: CheckedPlace
    /// The type of the value the place holds.
    var placeType: RayoType
    /// Where the source writes the `&` and the place.
    var range: SourceRange

    /// The place itself, as the value of a position that takes it and makes `use` of it, where the source writes the
    /// `&`.
    func placeExpression(as use: PlaceUse) -> CheckedExpr {
        CheckedExpr(kind: .place(place, use), type: placeType, range: range)
    }

    /// The place as the source writes it after the `&`, where a position takes it as a place written bare.
    var barePlace: BarePlace {
        BarePlace(place: place, placeType: placeType, range: range)
    }
}

extension LentPlace: WaitingValue {
    /// The type of the place's value, whatever the position.
    var type: RayoType? { placeType }

    var defaultType: RayoType? { placeType }

    func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
        TypeFit.fits(placeType, type)
    }

    var lendsPlace: Bool { true }

    /// The place, where `position` takes a reference, as a position that expects the place's type does, since the
    /// place's type is its own wherever it stands.
    func settled(toward type: RayoType?, at position: Position, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.lent(self, to: Expectation(placeType, at: position))
    }

    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.lent(self, to: expected)
    }

    /// Reports nothing: the place was checked as the source wrote it, and what the `&` gives it to failed for
    /// another reason.
    func reportErrors(by expressions: ExpressionChecker) {}
}
