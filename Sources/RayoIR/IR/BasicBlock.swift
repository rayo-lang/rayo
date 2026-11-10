public struct BasicBlock: Equatable, Sendable {
    public var statements: [Statement]
    public var terminator: Terminator

    public init(statements: [Statement], terminator: Terminator) {
        self.statements = statements
        self.terminator = terminator
    }
}
