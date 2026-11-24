public struct BasicBlock: Equatable, Sendable {
    public var statements: [Statement]
    public var terminator: Terminator

    public init(statements: [Statement], terminator: Terminator) {
        self.statements = statements
        self.terminator = terminator
    }

    /// The effects of each statement in turn, then those of the terminator.
    public var effects: [[Effect]] {
        statements.map(\.effects) + [terminator.effects]
    }
}
