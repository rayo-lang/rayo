import RayoCheckedProgram
import RayoSource

/// `mutable place`, checked on its own: the place it lends for change, the type of the value the place holds, and
/// where the source writes it. It waits for its position, since only the argument of a parameter that borrows for
/// change, and a `ref var`'s value, take it.
struct MutablyLentPlace {
    var place: CheckedPlace
    /// The type of the value the place holds.
    var placeType: RayoType
    /// Where the source writes the `mutable` and the place.
    var range: SourceRange

    /// The place itself, as the value of a position that takes it, where the source writes the `mutable`: a `ref
    /// var`'s value, which borrows it, or a call's argument, which passes the parameter the place itself.
    var placeExpression: CheckedExpr {
        CheckedExpr(kind: .place(place, .borrow), type: placeType, range: range)
    }
}

extension MutablyLentPlace: WaitingValue {
    /// The type of the place's value, whatever the position.
    var type: RayoType? { placeType }

    var defaultType: RayoType? { placeType }

    func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
        TypeFit.fits(placeType, type)
    }

    var lendsForChange: Bool { true }

    /// The place, where `position` takes a mutable reference, as a position that expects the place's type does, since
    /// the place's type is its own wherever it stands.
    func settled(toward type: RayoType?, at position: Position, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.mutablyLent(self, to: Expectation(placeType, at: position))
    }

    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.mutablyLent(self, to: expected)
    }

    /// Reports nothing: the place was checked as the source wrote it, and what the `mutable` gives it to failed for
    /// another reason.
    func reportErrors(by expressions: ExpressionChecker) {}
}
