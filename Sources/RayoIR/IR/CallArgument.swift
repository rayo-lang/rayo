/// What a call passes for one of its function's parameters.
public enum CallArgument: Equatable, Sendable {
    /// A value the call passes as it is: a constant, or a value that an owned parameter takes, as a primary
    /// initializer's does.
    case operand(Operand)
    /// An access to the place that holds the argument, which the parameter reaches it through, as a borrowed or
    /// `mutable` parameter does.
    case access(AccessID)
}
