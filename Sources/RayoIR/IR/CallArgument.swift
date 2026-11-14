/// What a call passes for one of its function's parameters.
public enum CallArgument: Equatable, Sendable {
    /// A value the call passes as it is: a constant, or a value that an owned parameter takes, as a primary
    /// initializer's does.
    case operand(Operand)
    /// An access to the place that holds the argument, which the parameter reaches it through, as a borrowed or
    /// `mutable` parameter does.
    case access(AccessID)

    /// The value the argument passes as it is, or nil where it passes an access.
    public var operand: Operand? {
        guard case .operand(let operand) = self else { return nil }
        return operand
    }

    /// The access the argument passes, or nil where it passes a value.
    public var access: AccessID? {
        guard case .access(let access) = self else { return nil }
        return access
    }
}
