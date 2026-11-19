/// The checked body of a function of the checked program.
public struct CheckedBody: Sendable {
    /// The body's locals, indexed by `LocalID`, its function's parameters first, in order.
    public var locals: [CheckedLocal]
    public var statements: [CheckedStmt]

    public init(locals: [CheckedLocal], statements: [CheckedStmt]) {
        self.locals = locals
        self.statements = statements
    }
}
