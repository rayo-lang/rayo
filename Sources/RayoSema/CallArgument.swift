import RayoCheckedProgram
import RayoSource

/// An argument of a call, as checking the call takes it: its label, where the source writes it, and its value. A
/// written call's argument is checked as the call is, while an implicit member's was checked on its own already,
/// since the member it passes it to is known only once the member's position gives its type.
protocol CallArgument {
    /// The label the argument is written with, or nil where it is written with none.
    var label: String? { get }
    /// Where the source writes the argument, its label included.
    var range: SourceRange { get }

    /// Checks the value against the type of the parameter that takes it, which `expected` names.
    func checked(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr?

    /// The value checked on its own, before the call has chosen the parameter that takes it, so an untyped value
    /// stays untyped and no parameter's type has settled it. Returns nil once it has reported a mistake.
    func uncheckedValue(by expressions: ExpressionChecker) -> CheckedValue?

    /// Reports the value's own errors, where no parameter takes it.
    func reportErrors(by expressions: ExpressionChecker)
}
