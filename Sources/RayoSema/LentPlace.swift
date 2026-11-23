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

    /// The place itself, as the value of a position that takes it, where the source writes the `&`.
    var placeExpression: CheckedExpr {
        CheckedExpr(kind: .place(place), type: placeType, range: range)
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

    /// Reports the `&`, since a position that expects at most a type takes no reference.
    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.file.errors.report(.unsupportedReference, at: range)
        return nil
    }

    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.lent(self, to: expected)
    }

    /// The place, where `recipient` takes a reference, as a position that expects the place's type does.
    func settled(takenBy recipient: Recipient, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.lent(self, to: Expectation(placeType, recipient: recipient))
    }

    /// Reports nothing: the place was checked as the source wrote it, and what the `&` gives it to failed for
    /// another reason.
    func reportErrors(by expressions: ExpressionChecker) {}
}
