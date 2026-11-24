import RayoCheckedProgram

/// A value that waits for its position only to give it a type: an untyped value, an array literal or an implicit
/// member. It settles to a type on its own, and its position then takes the value it settles to as it takes any typed
/// value.
protocol TypeWaitingValue: WaitingValue {
    /// Settles the value toward `type`: to `type` where it can, and otherwise as it would where its position gives no
    /// type. Reports what keeps it from settling, and returns nil then. An error that still leaves the value a meaning,
    /// such as a literal that `type` can't hold, is reported, and the value settles all the same.
    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr?
}

extension TypeWaitingValue {
    /// Settles the value toward `type`, then has `position` take the whole value.
    func settled(toward type: RayoType?, at position: Position, by expressions: ExpressionChecker) -> CheckedExpr? {
        // A value that failed to settle was reported.
        guard let settled = settled(toward: type, by: expressions) else { return nil }
        return expressions.taken(settled, by: position)
    }

    /// Settles the value toward the expected type, then makes the whole value fit it.
    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        // A value that failed to settle was reported.
        guard let settled = settled(toward: expected.type, by: expressions) else { return nil }
        return expressions.fitted(settled, to: expected)
    }
}
