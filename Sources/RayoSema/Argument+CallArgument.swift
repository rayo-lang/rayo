import RayoCheckedProgram
import RayoSyntax

/// A written call's argument, whose value is checked as the call is.
extension Argument: CallArgument {
    func checked(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        expressions.check(value, expecting: expected)
    }

    func uncheckedValue(by expressions: ExpressionChecker) -> CheckedValue? {
        expressions.value(of: value)
    }

    func reportErrors(by expressions: ExpressionChecker) {
        _ = expressions.check(value)
    }
}
