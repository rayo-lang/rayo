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

    /// Reports the errors the value gives on its own, and not those its parameter would have settled, such as an
    /// implicit member's want of a type, or a `&` given to no parameter that borrows.
    func reportErrors(by expressions: ExpressionChecker) {
        expressions.reportSettlingErrors(of: [expressions.value(of: value)])
    }
}
