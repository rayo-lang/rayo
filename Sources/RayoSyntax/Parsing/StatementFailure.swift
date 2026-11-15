/// Thrown by the parser once it has reported the syntax error that ended a statement in a block, with the names the
/// statement's `let` or `var` binds before the error.
struct StatementFailure: Error {
    /// The names of the bindings the parser read before the error, among them one whose name it read but whose type
    /// or value failed. A statement other than a `let` or a `var` binds none.
    var boundNames: [String] = []
}
