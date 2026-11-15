/// A value checked on its own whose type the position it stands in settles: an untyped value, an array literal, an
/// implicit member, or an `if` whose branches end in such values.
protocol WaitingValue {
    /// The type a part of the value fixes, whatever position it stands in, such as the type of an `if`'s typed
    /// branch; nil where only its position can give it one.
    var type: RayoType? { get }

    /// The type the value settles to where its position gives none, or nil where it can't settle to any then, as
    /// `[]` can't.
    var defaultType: RayoType? { get }

    /// Whether the value can settle to `type`, where `declarations` gives the members an implicit member names.
    func fits(_ type: RayoType, in declarations: Declarations) -> Bool

    /// Settles the value toward `type`: to `type` where it can, and otherwise as it would where its position gives
    /// no type. Reports what keeps it from settling, and returns nil then.
    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr?

    /// Settles the value to the type `expected` names, reporting each part of it that can't take that type with the
    /// error `expected` gives.
    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr?

    /// Reports the errors the value's parts give on their own, where the expression that holds it fails for another
    /// reason and so never settles it.
    func reportErrors(by expressions: ExpressionChecker)
}

extension WaitingValue {
    /// Settles the value toward the expected type, then makes the whole value fit it.
    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        // A value that failed to settle was reported.
        guard let settled = settled(toward: expected.type, by: expressions) else { return nil }
        return expressions.fitted(settled, to: expected)
    }
}
