extension Terminator {
    /// What the terminator does to places, in the order it does them.
    public var effects: [Effect] {
        var effects: [Effect] = []
        forEachEffect { effects.append($0) }
        return effects
    }

    /// Lends `visit` each of the terminator's effects in turn, and stops where it throws: it finds its operand's
    /// value, where it has one, and a return then leaves the function.
    func forEachEffect<Failure: Error>(_ visit: (Effect) throws(Failure) -> Void) throws(Failure) {
        try operand?.forEachEffect(visit)
        guard case .return = self else { return }
        try visit(.exit)
    }
}
