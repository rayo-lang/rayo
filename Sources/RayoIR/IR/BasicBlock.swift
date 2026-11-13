public struct BasicBlock: Equatable, Sendable {
    public var statements: [Statement]
    public var terminator: Terminator

    public init(statements: [Statement], terminator: Terminator) {
        self.statements = statements
        self.terminator = terminator
    }

    /// The operands the block uses, in the order it evaluates them: its statements' in turn, then its terminator's.
    public var operands: [Operand] {
        // A computation uses its value's operands, and a declaration uses none.
        let statementOperands = statements.flatMap { statement in
            switch statement {
            case .compute(_, let value, _): value.operands
            case .declare: [Operand]()
            }
        }

        // The terminator's operand, where it has one, is the block's last.
        return statementOperands + [terminator.operand].compactMap { $0 }
    }
}
