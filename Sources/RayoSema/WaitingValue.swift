import RayoCheckedProgram

/// A value checked on its own that waits for the position it stands in: an untyped value, an array literal or an
/// implicit member, whose type the position settles, a `&` or a `mutable` of a place, which only some positions
/// take, or an `if` whose branches end in such values.
protocol WaitingValue {
    /// The type a part of the value fixes, whatever position it stands in, such as the type of an `if`'s typed
    /// branch; nil where only its position can give it one.
    var type: RayoType? { get }

    /// The type the value settles to where its position gives none, or nil where it can't settle to any then, as
    /// `[]` can't.
    var defaultType: RayoType? { get }

    /// Whether the value fits `type`, as a call asks when it picks among overloads: it can settle to `type`, and
    /// `type` holds each integer literal's value. `declarations` gives the members an implicit member names.
    func fits(_ type: RayoType, in declarations: Declarations) -> Bool

    /// Whether settling the value to `type` gives a value of that type. A literal in it that `type` can't hold is
    /// reported as it settles, so the value can settle to a type it doesn't fit.
    func canSettle(to type: RayoType, in declarations: Declarations) -> Bool

    /// Whether the source writes the value as a `&` of a place.
    var lendsPlace: Bool { get }

    /// Whether the value, or any branch of it that runs to its end, is written as a `&` of a place.
    var mayLendPlace: Bool { get }

    /// Whether the source writes the value as a `mutable` of a place.
    var lendsForChange: Bool { get }

    /// Settles the value toward `type`: to `type` where it can, and otherwise as it would where its position gives
    /// no type. Reports what keeps it from settling, and returns nil then. An error that still leaves the value a
    /// meaning, such as a literal that `type` can't hold, is reported, and the value settles all the same.
    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr?

    /// Settles the value to the type `expected` names, reporting each part of it that can't take that type with the
    /// error `expected` gives.
    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr?

    /// Settles the value where its position gives no type, and `recipient` takes it, as a declaration takes its value
    /// where no annotation gives its type. Reports each part of it that the recipient can't take as the source writes
    /// it.
    func settled(takenBy recipient: Recipient, by expressions: ExpressionChecker) -> CheckedExpr?

    /// Reports the errors the value's parts give on their own, where the expression that holds it fails for another
    /// reason and so never settles it.
    func reportErrors(by expressions: ExpressionChecker)
}

extension WaitingValue {
    /// A value that holds no integer literal can settle to just the types it fits.
    func canSettle(to type: RayoType, in declarations: Declarations) -> Bool {
        fits(type, in: declarations)
    }

    /// No value but a `&` of a place, or an `if` whose branches end in one, is written as a `&`.
    var lendsPlace: Bool { false }

    var mayLendPlace: Bool { lendsPlace }

    /// No value but a `mutable` of a place, or an `if` whose branches end in one, is written as a `mutable`.
    var lendsForChange: Bool { false }

    /// Reports the errors that settling the value where its position gives no type reports.
    func reportErrors(by expressions: ExpressionChecker) {
        _ = settled(toward: nil, by: expressions)
    }

    /// Settles the value toward the expected type, then makes the whole value fit it.
    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        // A value that failed to settle was reported.
        guard let settled = settled(toward: expected.type, by: expressions) else { return nil }
        return expressions.fitted(settled, to: expected)
    }

    /// Settles the value as it would where its position gives no type, then hands the whole value to `recipient`.
    func settled(takenBy recipient: Recipient, by expressions: ExpressionChecker) -> CheckedExpr? {
        // A value that failed to settle was reported.
        guard let settled = settled(toward: nil, by: expressions) else { return nil }
        return expressions.taken(settled, by: recipient)
    }
}
