extension Terminator {
    /// What the terminator does to places, in the order it does them: it finds its operand's value, where it has one,
    /// and a return then leaves the function.
    public var effects: [Effect] {
        let operandEffects = operand?.effects ?? []
        guard case .return = self else { return operandEffects }
        return operandEffects + [.exit]
    }
}
