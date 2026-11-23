import RayoCheckedProgram
import RayoSource

/// `&place`, checked on its own: the place it lends, the type of the value the place holds, and where the source
/// writes it. Only the argument of a parameter that borrows takes it, so it waits for its position to say whether
/// that is what the position is.
struct LentPlace {
    var place: CheckedPlace
    /// The type of the value the place holds.
    var placeType: RayoType
    /// Where the source writes the `&` and the place.
    var range: SourceRange
}

extension LentPlace: WaitingValue {
    /// The type of the place's value, which is the type of the parameter's argument whatever the position.
    var type: RayoType? { placeType }

    var defaultType: RayoType? { placeType }

    func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
        TypeFit.fits(placeType, type)
    }

    var lendsPlace: Bool { true }

    /// Reports the `&`, since a position that expects at most a type is no call's argument.
    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.file.errors.report(.unsupportedReference, at: range)
        return nil
    }

    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.lent(self, to: expected)
    }

    /// Reports nothing: the place was checked as the source wrote it, and what the `&` gives it to failed for
    /// another reason.
    func reportErrors(by expressions: ExpressionChecker) {}
}
