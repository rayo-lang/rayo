public struct BasicBlock: Equatable, Sendable {
    public var statements: [Statement]
    public var terminator: Terminator

    public init(statements: [Statement], terminator: Terminator) {
        self.statements = statements
        self.terminator = terminator
    }

    /// Lends `visit` each effect of each statement in turn, then each of the terminator's, and stops where it throws.
    /// A check that reads the effects once walks them so, since the walk builds no array of them.
    package func forEachEffect<Failure: Error>(_ visit: (Effect) throws(Failure) -> Void) throws(Failure) {
        for statement in statements { try statement.forEachEffect(visit) }
        try terminator.forEachEffect(visit)
    }
}
